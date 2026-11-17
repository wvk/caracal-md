require 'rbconfig'

RSpec.describe Caracal::Md::CodeHandlers do
  def block(source = 'a -> b', language: 'dot', attributes: {})
    Caracal::Md::CodeBlock.new(language: language, source: source, attributes: attributes)
  end

  def render(handlers, code_block = block)
    warnings = []
    bytes = handlers.render(code_block) { |message| warnings << message }
    [bytes, warnings]
  end

  it 'returns the image a handler makes, matching languages case-insensitively' do
    handlers = described_class.new('DOT' => ->(_) { png })
    expect(handlers.handles?('dot')).to be(true)
    expect(render(handlers)).to eq([png, []])
  end

  it 'refuses what is not a PNG, JPEG or GIF of readable size' do
    {
      nil                       => 'returned NilClass',
      ''                        => 'returned nothing',
      '<svg/>'                  => 'returned no PNG, JPEG or GIF image',
      "\x89PNG\r\n\x1a\n".b     => 'returned no PNG, JPEG or GIF image',
      'BM' + "\0" * 60          => 'returned no PNG, JPEG or GIF image',
      ['bytes']                 => 'returned Array',
      StringIO.new(png)         => 'returned StringIO',
    }.each do |result, message|
      bytes, warnings = render(described_class.new('dot' => ->(_) { result }))
      expect(bytes).to be_nil
      expect(warnings.first).to include(message)
    end
  end

  it 'refuses images over max_bytes' do
    bytes, warnings = render(described_class.new({ 'dot' => ->(_) { png } }, max_bytes: 10))
    expect(bytes).to be_nil
    expect(warnings.first).to include('more than 10')
  end

  it 'turns exceptions into a short warning' do
    bytes, warnings = render(described_class.new('dot' => ->(_) { raise IOError, "line\n" * 200 }))
    expect(bytes).to be_nil
    expect(warnings.first).to start_with('dot handler failed (IOError: line line').and end_with('shown as code')
    expect(warnings.first.length).to be < 400
  end

  it 'runs identical blocks once and at most max_calls blocks' do
    calls = 0
    handlers = described_class.new({ 'dot' => ->(_) { calls += 1; png } }, max_calls: 2)
    3.times { render(handlers, block('same')) }
    expect(calls).to eq(1)

    render(handlers, block('other'))
    bytes, warnings = render(handlers, block('third'))
    expect(calls).to eq(2)
    expect(bytes).to be_nil
    expect(warnings.first).to include('more than 2 code blocks')
  end

  it 'starts afresh for each render' do
    handlers = described_class.new({ 'dot' => ->(_) { png } }, max_calls: 1)
    render(handlers, block('one'))
    expect(render(handlers.for_render, block('two')).first).to eq(png)
  end

  it 'insists on callable handlers' do
    expect { described_class.new('dot' => 'dot -Tpng') }.to raise_error(ArgumentError, /respond to call/)
  end
end

RSpec.describe 'rendering fenced blocks through code handlers' do
  def render(markdown, handlers, **options)
    @renderer = Caracal::Md::Renderer.new(code_handlers: handlers, **options)
    document_xml(@renderer.render(markdown))
  end

  it 'shows the image with caption, id and size from the block attributes' do
    seen = nil
    handler = ->(code_block) { seen = code_block; png(400, 100) }
    doc = render(<<~MD, { 'mermaid' => handler }, number_captions: true)
      See [](#fig-flow).

      ```mermaid
      graph LR; A-->B
      ```
      {: #fig-flow title="Flow" width="50%" theme="dark"}
    MD

    expect(seen.language).to eq('mermaid')
    expect(seen.source).to eq('graph LR; A-->B')
    expect(seen.attributes).to eq('id' => 'fig-flow', 'title' => 'Flow', 'width' => '50%', 'theme' => 'dark')
    expect([seen.source, seen.attributes]).to all(be_frozen)

    expect(doc.at_xpath('//wp:extent/@cx', NS).value.to_i).to eq((9026 / 20.0 / 2).round * 12_700)
    expect(doc.at_xpath('//wp:docPr/@descr', NS)&.value.to_s).not_to include('graph')
    expect(body_text(doc)).to eq('See Figure 1.Figure 1: Flow')
    expect(@renderer.warnings).to be_empty
  end

  it 'renders $$ math through the math handler' do
    doc = render("$$\nx^2\n$$\n", { 'math' => ->(code_block) { png if code_block.source == 'x^2' } })
    expect(doc.at_xpath('//w:drawing', NS)).not_to be_nil
  end

  it 'keeps the code when the handler fails, and other languages as they were' do
    doc = render("```dot\nbroken\n```\n\n```ruby\nputs 1\n```\n", { 'dot' => ->(_) { raise 'syntax error' } })
    expect(doc.at_xpath('//w:drawing', NS)).to be_nil
    expect(body_text(doc)).to eq('brokenputs 1')
    expect(@renderer.warnings).to eq(['dot handler failed (RuntimeError: syntax error); shown as code'])
  end

  it 'works in #markdown' do
    docx = Caracal::Document.new
    docx.markdown "```dot\na -> b\n```\n", code_handlers: { 'dot' => ->(_) { png } }
    expect(document_xml(docx.render.string).at_xpath('//w:drawing', NS)).not_to be_nil
  end
end

RSpec.describe Caracal::Md::CommandHandler do
  let(:ruby) { RbConfig.ruby }

  def block(source = 'input')
    Caracal::Md::CodeBlock.new(language: 'x', source: source, attributes: {})
  end

  it 'passes the source on stdin and returns stdout as bytes' do
    handler = described_class.new([ruby, '-e', 'STDOUT.binmode.write(STDIN.binmode.read.reverse)'])
    result = handler.call(block("\xFFabc".b))
    expect(result).to eq("cba\xFF".b)
    expect(result.encoding).to eq(Encoding::BINARY)
  end

  it 'splits a command string into arguments without a shell' do
    handler = described_class.new(%(#{ruby} -e "print ARGV.inspect" -- "a b" '$(id)' ';' x))
    expect(handler.call(block)).to eq('["a b", "$(id)", ";", "x"]')
  end

  it 'runs in an empty temporary directory, removed afterwards' do
    handler = described_class.new([ruby, '-e', 'print Dir.pwd, " ", Dir.children(".").inspect'])
    dir, children = handler.call(block).split(' ', 2)
    expect(children).to eq('[]')
    expect(File.basename(dir)).to start_with('caracal-md-')
    expect(File.exist?(dir)).to be(false)
  end

  it 'raises with the end of stderr when the program fails' do
    handler = described_class.new([ruby, '-e', 'warn "x" * 10_000 + " the reason"; exit 3'])
    expect { handler.call(block) }.to raise_error(described_class::Error, /exited with 3: x+ the reason\z/) do |error|
      expect(error.message.length).to be < 4200
    end
  end

  it 'kills the program and what it started on timeout' do
    script = 'pid = spawn(RbConfig.ruby, "-e", "sleep 30"); File.write(ARGV[0], pid.to_s); sleep 30'
    Dir.mktmpdir do |dir|
      pid_file = File.join(dir, 'child')
      handler  = described_class.new([ruby, '-rrbconfig', '-e', script, pid_file], timeout: 1)
      started  = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      expect { handler.call(block) }.to raise_error(described_class::Error, /timed out after 1s/)
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 5

      child = File.read(pid_file).to_i
      expect(running_after_grace?(child)).to be(false)
    end
  end

  # Whether +pid+ still runs after up to two seconds; zombies count as ended.
  def running_after_grace?(pid)
    20.times do
      state = File.read("/proc/#{pid}/stat")[/\) (\S)/, 1] rescue nil
      return false if state.nil? or state == 'Z'

      sleep 0.1
    end
    true
  end

  it 'stops at max_bytes of output' do
    handler = described_class.new([ruby, '-e', 'loop { print "x" * 65_536 }'], max_bytes: 100_000)
    expect { handler.call(block) }.to raise_error(described_class::Error, /more than 100000 bytes/)
  end

  it 'copes with programs that do not read their input' do
    handler = described_class.new([ruby, '-e', 'print "ok"'])
    expect(handler.call(block('x' * 1_000_000))).to eq('ok')
  end

  it 'reports a missing program' do
    expect { described_class.new('no-such-program-here').call(block) }.to raise_error(SystemCallError)
  end

  it 'renders Graphviz diagrams', if: system('command -v dot >/dev/null 2>&1') do
    bytes = described_class.new(%w[dot -Tpng]).call(block('digraph { a -> b }'))
    expect(Caracal::ImageSize.read(bytes)).to be_an(Array)
  end
end
