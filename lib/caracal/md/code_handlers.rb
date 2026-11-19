require 'digest'
require 'json'

module Caracal
  module Md
    # A fenced code block handed to a code handler. All three come from the
    # Markdown author: +language+ the fence's info string (or "math" for
    # $$ blocks), +source+ the block's text, +attributes+ the block's IAL
    # (id, title, width, …) as a frozen Hash of Strings.
    CodeBlock = Data.define(:language, :source, :attributes)

    # The code handlers of one render: language => handler, where a handler
    # is anything that responds to call(code_block) and returns image bytes
    # (Caracal::Md::CommandHandler runs a program; other runners can come
    # from anywhere).
    #
    # What a handler returns is untrusted, like an image from the web: only
    # a non-empty String of at most max_bytes holding a PNG, JPEG or GIF
    # whose size can be read, or an SVG (cleaned later, see Svg), passes;
    # with raster_only, no SVG. Anything else, an exception included, gives
    # nil and a warning. Identical blocks run once; at most max_calls blocks
    # run per document.
    #
    # With a +cache+ (an ActiveSupport::Cache::Store, a FileCache, anything
    # with fetch(key) { value }), successful output outlives the render:
    # later renders take it from the cache instead of running the handler.
    # The key is a digest of the handler's cache_key (its language when it
    # has none), the block's language, source and attributes. Cached bytes
    # pass the same checks as fresh ones, since a shared cache is untrusted
    # storage, and count for the identical-block rule, not for max_calls.
    class CodeHandlers
      DEFAULT_MAX_CALLS = 50
      DEFAULT_MAX_BYTES = 20 * 1024 * 1024
      MESSAGE_LENGTH    = 300
      CACHE_NAMESPACE   = 'caracal-md/code/'.freeze

      # Raised in the cache's fetch block for output not to store.
      class Uncached < StandardError; end

      attr_reader :max_calls, :max_bytes, :cache

      # +handlers+: { language => handler }; languages match case-insensitively.
      # Without braces, new('dot' => handler) passes them as keywords.
      def initialize(handlers = {}, max_calls: DEFAULT_MAX_CALLS, max_bytes: DEFAULT_MAX_BYTES, raster_only: false, cache: nil, **more)
        @handlers = handlers.to_h.merge(more).to_h do |language, handler|
          raise ArgumentError, "code handler for #{language.inspect} does not respond to call" unless handler.respond_to?(:call)

          [language.to_s.downcase, handler]
        end
        @max_calls   = max_calls
        @max_bytes   = max_bytes
        @raster_only = raster_only
        @cache       = cache
        raise ArgumentError, 'code cache does not respond to fetch' if cache and not cache.respond_to?(:fetch)
      end

      def handles?(language)
        @handlers.key?(language.to_s.downcase)
      end

      def empty?
        @handlers.empty?
      end

      # A fresh copy for one render, so call counts and results stay apart.
      def for_render(cache: @cache)
        self.class.new(@handlers, max_calls: @max_calls, max_bytes: @max_bytes, raster_only: @raster_only, cache: cache)
      end

      # The image bytes for +block+, or nil with a warning yielded.
      def render(block)
        key = [block.language.to_s.downcase, block.source, block.attributes]
        @results ||= {}
        bytes, message = @results.fetch(key) { @results[key] = @cache ? cached(block) : run(block) }
        yield message if message and block_given?
        bytes
      end

      # The cache key of +block+: the handler's cache_key, or its language
      # without one, with the block's language, source and attributes.
      def cache_key(block)
        handler = @handlers.fetch(block.language.to_s.downcase)
        handler_key = (handler.cache_key if handler.respond_to?(:cache_key))
        material = [handler_key, @raster_only, block.language.to_s.downcase, block.source.to_s, block.attributes.to_h.sort]
        CACHE_NAMESPACE + Digest::SHA256.hexdigest(JSON.generate(material))
      end

      private

      # Output from the cache, else from the handler, stored when it passes
      # the checks. A cache entry that fails them runs the handler, which
      # replaces it where the cache can write. Errors of the cache itself
      # propagate.
      def cached(block)
        key   = cache_key(block)
        fresh = nil
        bytes = @cache.fetch(key) do
          fresh = run(block)
          raise Uncached unless fresh.first

          fresh.first
        end
        return fresh if fresh
        return [bytes.b, nil] unless check(bytes)

        result = run(block)
        @cache.write(key, result.first) if result.first and @cache.respond_to?(:write)
        result
      rescue Uncached
        fresh
      end

      def run(block)
        @calls = @calls.to_i + 1
        return [nil, "#{block.language}: more than #{@max_calls} blocks to render"] if @calls > @max_calls

        bytes = @handlers.fetch(block.language.to_s.downcase).call(block)
        problem = check(bytes)
        problem ? [nil, "#{block.language} handler #{problem}"] : [bytes.b, nil]
      rescue StandardError => e
        [nil, "#{block.language} handler failed (#{e.class}: #{shorten(e.message)})"]
      end

      def check(bytes)
        return "returned #{bytes.class}, not image bytes" unless bytes.is_a?(String)
        return 'returned nothing' if bytes.empty?
        return "returned #{bytes.bytesize} bytes, more than #{@max_bytes}" if bytes.bytesize > @max_bytes

        return if Caracal::ImageSize.read(bytes)
        return if Svg.svg?(bytes) and not @raster_only

        @raster_only ? 'returned no PNG, JPEG or GIF image' : 'returned no PNG, JPEG, GIF or SVG image'
      end

      def shorten(message)
        message = message.to_s.gsub(/\s+/, ' ').strip
        message.length > MESSAGE_LENGTH ? "#{message[0, MESSAGE_LENGTH]}…" : message
      end
    end
  end
end
