require 'net/http'
require 'uri'

module Caracal
  module Md
    # Reads image bytes for an image source. Local paths must resolve inside
    # base_dir; http(s) URLs are fetched only with allow_remote. Returns nil for
    # anything it refuses or can't read, so the converter falls back to alt text.
    class ImageLoader
      DATA_URI = %r{\Adata:image/[\w.+-]+;base64,(.*)\z}m

      attr_reader :base_dir

      def initialize(base_dir: Dir.pwd, allow_remote: false, max_bytes: 20 * 1024 * 1024, timeout: 10)
        @base_dir     = File.realpath(base_dir.to_s)
        @allow_remote = allow_remote
        @max_bytes    = max_bytes
        @timeout      = timeout
      end

      def call(src)
        case src
        when DATA_URI                   then Regexp.last_match(1).unpack1('m')
        when %r{\Ahttps?://}i           then fetch(src) if @allow_remote
        when %r{\A[a-z][a-z0-9+.-]*:}i  then nil # file:, javascript: and friends
        else local(src)
        end
      end

      private

      def local(src)
        path = URI::RFC2396_PARSER.unescape(src.to_s.split(/[?#]/).first.to_s)
        return if path.empty?

        full = File.expand_path(path, @base_dir)
        real = File.realpath(full)
        return unless real.start_with?(@base_dir + File::SEPARATOR)
        return unless File.file?(real) and File.size(real) <= @max_bytes

        File.binread(real)
      rescue SystemCallError
        nil
      end

      def fetch(src, redirects = 3)
        uri = URI.parse(src)
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: @timeout, read_timeout: @timeout) do |http|
          http.request(Net::HTTP::Get.new(uri)) do |response|
            case response
            when Net::HTTPRedirection
              return redirects.positive? ? fetch(URI.join(src, response['location']).to_s, redirects - 1) : nil
            when Net::HTTPSuccess
              body = +''
              response.read_body do |chunk|
                body << chunk
                return nil if body.bytesize > @max_bytes
              end
              return body
            else
              return nil
            end
          end
        end
      rescue StandardError
        nil
      end
    end
  end
end
