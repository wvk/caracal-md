require 'open3'
require 'shellwords'
require 'tmpdir'

module Caracal
  module Md
    # A code handler that runs a program: the block's source goes to its
    # stdin, the image comes from its stdout.
    #
    #   Caracal::Md::CommandHandler.new(%w[dot -Tpng])
    #   Caracal::Md::CommandHandler.new('plantuml -tpng -pipe', timeout: 60)
    #
    # The command is an argument list (a String is split like a shell would,
    # without running one), so nothing from the document reaches a command
    # line. The program runs in an empty temporary directory, in a process
    # group of its own that is killed when it is done, on timeout or when its
    # output exceeds max_bytes. Relative paths in the source find no files;
    # absolute ones still do, so untrusted documents need the program in a
    # sandbox (see README).
    class CommandHandler
      class Error < StandardError; end

      CHUNK      = 64 * 1024
      STDERR_MAX = 4 * 1024

      attr_reader :command

      def initialize(command, timeout: 30, max_bytes: CodeHandlers::DEFAULT_MAX_BYTES, env: {})
        @command   = command.is_a?(String) ? Shellwords.split(command) : Array(command).map(&:to_s)
        raise ArgumentError, 'empty command' if @command.empty?

        @timeout   = timeout
        @max_bytes = max_bytes
        @env       = env.to_h.transform_keys(&:to_s)
      end

      def call(block)
        Dir.mktmpdir('caracal-md-') { |dir| run(block.source.to_s, dir) }
      end

      private

      def run(input, dir)
        deadline = now + @timeout
        stdin, stdout, stderr, wait = Open3.popen3(@env, *@command, chdir: dir, pgroup: true)
        [stdin, stdout, stderr].each(&:binmode)
        writer = Thread.new { feed(stdin, input) }
        out, err = drain(stdout, stderr, deadline)

        raise Error, "#{@command.first} timed out after #{@timeout}s" unless wait.join([deadline - now, 0].max)

        status = wait.value
        raise Error, "#{@command.first} exited with #{status.exitstatus || status}: #{err.strip}" unless status.success?

        out
      ensure
        kill_group(wait) if wait
        writer&.kill
        [stdin, stdout, stderr].each { |io| io.close if io and not io.closed? }
      end

      def feed(stdin, input)
        stdin.write(input)
      rescue IOError, SystemCallError
        nil # the program stopped reading
      ensure
        stdin.close unless stdin.closed?
      end

      # stdout up to max_bytes and the end of stderr, until both close.
      def drain(stdout, stderr, deadline)
        out = String.new(encoding: Encoding::BINARY)
        err = String.new(encoding: Encoding::BINARY)
        open_ios = [stdout, stderr]
        until open_ios.empty?
          remaining = deadline - now
          ready, = IO.select(open_ios, nil, nil, remaining) if remaining.positive?
          raise Error, "#{@command.first} timed out after #{@timeout}s" unless ready

          ready.each do |io|
            chunk = io.read_nonblock(CHUNK, exception: false)
            next if chunk == :wait_readable
            next open_ios.delete(io) if chunk.nil?

            if io.equal?(stdout)
              out << chunk
              raise Error, "#{@command.first} wrote more than #{@max_bytes} bytes" if out.bytesize > @max_bytes
            else
              err << chunk
              err = err.byteslice(-STDERR_MAX, STDERR_MAX) if err.bytesize > STDERR_MAX
            end
          end
        end
        [out, err.force_encoding(Encoding::UTF_8).scrub]
      end

      # Ends the program and whatever it started.
      def kill_group(wait)
        Process.kill('KILL', -wait.pid)
      rescue SystemCallError
        nil
      ensure
        wait.join
      end

      def now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
