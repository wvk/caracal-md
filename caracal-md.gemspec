require_relative 'lib/caracal/md/version'

Gem::Specification.new do |s|
  s.name        = 'caracal-md'
  s.version     = Caracal::Md::VERSION
  s.authors     = ['Willem van Kerkhof']
  s.summary     = 'Render Markdown to DOCX with caracal, styled by a default theme or your own Word template.'
  s.description = 'caracal-md converts Markdown (GFM plus kramdown extensions) into Word documents through caracal. ' \
                  'It ships a default style set and merges the result into user-provided .docx/.dotx templates, ' \
                  'resolving styles by name so localized templates work too.'
  s.homepage    = 'https://github.com/wvk/caracal-md'
  s.license     = 'MIT'

  s.metadata = {
    'source_code_uri'       => s.homepage,
    'changelog_uri'         => "#{s.homepage}/blob/master/CHANGELOG.md",
    'bug_tracker_uri'       => "#{s.homepage}/issues",
    'rubygems_mfa_required' => 'true',
  }

  s.required_ruby_version = '>= 3.3'
  s.require_paths         = ['lib']
  s.bindir                = 'bin'
  s.executables           = ['caracal-md']
  s.files                 = Dir.glob(['{lib,bin}/**/*', 'README.md', 'CHANGELOG.md', 'LICENSE.txt', 'caracal-md.gemspec'], base: __dir__)

  s.add_dependency 'caracal',             '~> 2.0'
  s.add_dependency 'kramdown',            '~> 2.4'
  s.add_dependency 'kramdown-parser-gfm', '~> 1.1'
  s.add_dependency 'nokogiri',            '>= 1.16.2', '< 2.0'
  s.add_dependency 'rubyzip',             '>= 1.1.6', '< 4.0'
end
