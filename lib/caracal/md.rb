require 'caracal'

module Caracal
  # Markdown to DOCX through caracal.
  #
  #   Caracal::Md.render(markdown)                          # => DOCX bytes, default styles
  #   Caracal::Md.render(markdown, template: 'corp.dotx')   # => DOCX bytes in a Word template
  #   Caracal::Md.convert_file('notes.md')                  # writes notes.docx
  #
  #   Caracal::Document.save('report.docx') do |docx|       # Markdown inside a caracal document
  #     docx.h1 'Report'
  #     docx.markdown File.read('summary.md')
  #   end
  module Md
    class Error < StandardError; end

    def self.render(markdown, **options)
      Renderer.new(**options).render(markdown)
    end

    def self.save(markdown, path, **options)
      File.binwrite(path, render(markdown, **options))
      path
    end

    # Converts a Markdown file; images resolve relative to it.
    def self.convert_file(input, output = nil, **options)
      output ||= input.sub(/\.(md|markdown|mdown|mkd)\z/i, '') + '.docx'
      save(File.read(input, encoding: 'UTF-8'), output, base_dir: File.dirname(File.expand_path(input)), **options)
    end

    # A document showing every style of the default set. Change its styles in
    # Word and pass it back as template:.
    def self.reference_document(**options)
      render(File.read(File.join(__dir__, 'md', 'reference.md'), encoding: 'UTF-8'), highlight: true, **options)
    end
  end
end

require_relative 'md/version'
require_relative 'md/package'
require_relative 'md/styles'
require_relative 'md/settings'
require_relative 'md/numbering'
require_relative 'md/front_matter'
require_relative 'md/image_loader'
require_relative 'md/svg'
require_relative 'md/highlighter'
require_relative 'md/code_handlers'
require_relative 'md/command_handler'
require_relative 'md/placeholders'
require_relative 'md/parser'
require_relative 'md/captions'
require_relative 'md/converter'
require_relative 'md/template'
require_relative 'md/template_merger'
require_relative 'md/caption_fields'
require_relative 'md/post_processor'
require_relative 'md/core_properties'
require_relative 'md/language'
require_relative 'md/renderer'
require_relative 'md/document_extension'
