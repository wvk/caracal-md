require 'caracal/md'
require 'tmpdir'
require_relative 'support/template_builder'
require_relative 'support/docx_helpers'

NS = DocxHelpers::NS

RSpec.configure do |config|
  config.include DocxHelpers
  config.example_status_persistence_file_path = '.rspec_status'
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |c| c.syntax = :expect }
end
