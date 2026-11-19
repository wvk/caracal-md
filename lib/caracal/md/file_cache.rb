require 'digest'
require 'fileutils'
require 'securerandom'

module Caracal
  module Md
    # A cache in a directory, one file per key, for code handler output
    # (see CodeHandlers): the CLI's --code-cache. Writes go through a
    # temporary file, so concurrent renders read whole entries only.
    class FileCache
      attr_reader :dir

      def initialize(dir)
        @dir = File.expand_path(dir.to_s)
      end

      def fetch(key)
        path = path(key)
        return File.binread(path) if File.file?(path)

        value = yield
        write(key, value)
        value
      end

      def write(key, value)
        FileUtils.mkdir_p(@dir)
        path = path(key)
        temp = "#{path}.#{SecureRandom.hex(8)}.tmp"
        File.binwrite(temp, value.to_s)
        File.rename(temp, path)
        temp = nil
        value
      ensure
        File.delete(temp) if temp and File.exist?(temp)
      end

      def delete(key)
        File.delete(path(key))
        true
      rescue Errno::ENOENT
        false
      end

      private

      def path(key)
        File.join(@dir, Digest::SHA256.hexdigest(key.to_s))
      end
    end
  end
end
