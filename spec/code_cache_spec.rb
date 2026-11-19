require 'rbconfig'

RSpec.describe 'code cache' do
  # A cache with ActiveSupport's fetch: it stores what the block returns
  # and nothing when the block raises; with_write adds #write.
  def memory_cache(with_write: false)
    Class.new do
      attr_reader :data

      def initialize
        @data = {}
      end

      def fetch(key)
        @data.key?(key) ? @data[key] : (@data[key] = yield)
      end
    end.tap { |cache| cache.define_method(:write) { |key, value| @data[key] = value } if with_write }.new
  end

  def counting(result = nil, &block)
    calls = []
    handler = lambda do |code|
      calls << code
      block ? block.call(code) : (result || png)
    end
    [handler, calls]
  end

  def diagram(source = 'a -> b', attributes = '')
    "```dot\n#{source}\n```\n#{attributes}"
  end

  def render(markdown, handler, cache, **options)
    handlers = (handler.is_a?(Caracal::Md::CodeHandlers) ? handler : { 'dot' => handler })
    renderer = Caracal::Md::Renderer.new(code_handlers: handlers, code_cache: cache, **options)
    doc = document_xml(renderer.render(markdown))
    [doc, renderer.warnings]
  end

  it 'calls no handler in a second render with the same cache' do
    handler, calls = counting
    cache = memory_cache
    2.times do
      doc, warnings = render(diagram, handler, cache)
      expect(doc.xpath('//w:drawing', NS).size).to eq(1)
      expect(warnings).to be_empty
    end
    expect(calls.size).to eq(1)
    expect(cache.data.keys).to all(match(%r{\Acaracal-md/code/\h{64}\z}))
  end

  it 'runs the handler for a changed source, attribute or handler cache key' do
    handler, calls = counting
    cache = memory_cache
    render(diagram, handler, cache)
    render(diagram('a -> c'), handler, cache)
    render(diagram('a -> b', '{: width="50%"}'), handler, cache)
    expect(calls.map(&:source)).to eq(['a -> b', 'a -> c', 'a -> b'])

    keyed = Struct.new(:cache_key, :calls) do
      def call(_block)
        calls << cache_key
        DocxHelpers.instance_method(:png).bind_call(self)
      end
    end
    one = keyed.new('dot 13', [])
    two = keyed.new('dot 14', [])
    render(diagram, one, cache)
    render(diagram, one, cache)
    render(diagram, two, cache)
    expect(one.calls.size + two.calls.size).to eq(2)
  end

  it 'caches handlers without a cache key under their language' do
    first, first_calls = counting
    second, second_calls = counting
    cache = memory_cache
    render(diagram, first, cache)
    render(diagram, second, cache)
    expect([first_calls.size, second_calls.size]).to eq([1, 0])
  end

  it 'stores no failures, and runs the handler again next time' do
    handler, calls = counting('not an image')
    cache = memory_cache
    2.times do
      _, warnings = render(diagram, handler, cache)
      expect(warnings.first).to include('dot handler returned no PNG')
    end
    expect(calls.size).to eq(2)
    expect(cache.data).to be_empty
  end

  it 'checks cached bytes like fresh ones, and replaces a bad entry where the cache can write' do
    [memory_cache, memory_cache(with_write: true)].each do |cache|
      handler, calls = counting
      key = Caracal::Md::CodeHandlers.new('dot' => handler).cache_key(Caracal::Md::CodeBlock.new(language: 'dot', source: 'a -> b', attributes: {}))
      cache.data[key] = '<html>not an image</html>'
      doc, warnings = render(diagram, handler, cache)
      expect(doc.xpath('//w:drawing', NS).size).to eq(1)
      expect(warnings).to be_empty
      expect(calls.size).to eq(1)
      expect(cache.data[key]).to eq(cache.respond_to?(:write) ? png : '<html>not an image</html>')
    end
  end

  it 'counts cached blocks for identical blocks, not for max_calls' do
    handler, calls = counting
    cache = memory_cache
    sources = %w[a b c]
    handlers = Caracal::Md::CodeHandlers.new({ 'dot' => handler }, max_calls: 2)
    markdown = sources.map { |source| diagram(source) }.join("\n")
    render(markdown, handlers, cache).then { |_, warnings| expect(warnings.size).to eq(1) }
    expect(calls.size).to eq(2)

    doc, warnings = render(markdown + "\n" + diagram('a') + "\n" + diagram('d'), handlers, cache)
    expect(warnings).to be_empty
    expect(doc.xpath('//w:drawing', NS).size).to eq(5)
    expect(calls.map(&:source)).to eq(%w[a b c d])
  end

  it 'keeps SVG rasterizer output too' do
    svg = %(<svg xmlns="http://www.w3.org/2000/svg" width="40" height="20"><rect width="40" height="20"/></svg>)
    rasterizer, calls = counting
    cache = memory_cache
    2.times do
      Caracal::Md.render('![plan](plan.svg)', image_loader: ->(_) { svg }, svg_rasterizer: rasterizer, code_cache: cache)
    end
    expect(calls.size).to eq(1)
  end

  it 'refuses caches without fetch' do
    expect { Caracal::Md::CodeHandlers.new({}, cache: Object.new) }.to raise_error(ArgumentError, /fetch/)
  end

  describe Caracal::Md::CommandHandler do
    it 'names its command and version as cache key' do
      expect(described_class.new('dot -Tpng').cache_key).to eq([%w[dot -Tpng]])
      expect(described_class.new(%w[dot -Tpng], version: 14).cache_key).to eq([%w[dot -Tpng], '14'])
    end
  end

  describe Caracal::Md::FileCache do
    it 'keeps values in files named by the key digest' do
      Dir.mktmpdir do |dir|
        cache = described_class.new(File.join(dir, 'cache'))
        expect(cache.fetch('k') { png }).to eq(png)
        expect(cache.fetch('k') { raise 'not called' }).to eq(png)
        expect(Dir.children(File.join(dir, 'cache'))).to eq([Digest::SHA256.hexdigest('k')])
        expect { cache.fetch('j') { raise ArgumentError } }.to raise_error(ArgumentError)
        expect(Dir.children(File.join(dir, 'cache')).size).to eq(1)
        cache.write('k', 'new')
        expect(cache.fetch('k') { 'unused' }).to eq('new')
        expect(cache.delete('k')).to be(true)
        expect(cache.delete('k')).to be(false)
      end
    end
  end

  describe 'caracal-md --code-cache' do
    it 'runs the code handler once for two runs' do
      Dir.mktmpdir do |dir|
        image = File.join(dir, 'image.png')
        log   = File.join(dir, 'calls.log')
        script = File.join(dir, 'handler.rb')
        File.binwrite(image, png)
        File.write(script, "File.write(#{log.inspect}, 'run\\n', mode: 'a')\n$stdout.binmode\n$stdout.write(File.binread(#{image.inspect}))\n")
        args = ['--code-handler', "dot=#{RbConfig.ruby} #{script}", '--code-cache', File.join(dir, 'cache')]
        2.times { expect(document_xml(cli(diagram, *args)).xpath('//w:drawing', NS).size).to eq(1) }
        expect(File.readlines(log).size).to eq(1)
      end
    end
  end
end
