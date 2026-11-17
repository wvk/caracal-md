RSpec.describe Caracal::Md::ImageLoader do
  around { |example| Dir.mktmpdir { |dir| @dir = dir; example.run } }

  let(:loader) { described_class.new(base_dir: @dir) }

  it 'reads files inside base_dir' do
    File.binwrite(File.join(@dir, 'a b.png'), 'PNG')
    expect(loader.call('a%20b.png')).to eq('PNG')
    expect(loader.call('./a b.png?x=1')).to eq('PNG')
  end

  it 'refuses paths outside base_dir, symlinks included' do
    outside = Dir.mktmpdir
    File.write(File.join(outside, 'secret.png'), 'secret')
    File.symlink(File.join(outside, 'secret.png'), File.join(@dir, 'link.png'))
    expect(loader.call("#{outside}/secret.png")).to be_nil
    expect(loader.call('../secret.png')).to be_nil
    expect(loader.call('link.png')).to be_nil
  end

  it 'decodes data URIs' do
    expect(loader.call("data:image/png;base64,#{['PNG'].pack('m0')}")).to eq('PNG')
  end

  it 'fetches nothing remote unless allowed, and no other schemes' do
    expect(loader.call('https://example.com/x.png')).to be_nil
    expect(loader.call('file:///etc/passwd')).to be_nil
  end
end
