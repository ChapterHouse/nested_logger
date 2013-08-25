class NestedLogger::Logger

  attr_reader :depth, :io_or_logger_class
  attr_accessor :log_method

  def initialize(io_or_logger_class=$stdout)
    @depth = 0
    @io_or_logger_class = io_or_logger_class
  end

  def depth=(new_depth)
    new_depth = new_depth.to_i
    new_depth = 0 if new_depth < 0
    @depth = new_depth
  end

  def log(*messages)
    messages.each do |message|
      text = "#{message.to_s.indent(depth, '  ')}"
      begin
        case log_method
          when nil, :write
            io_or_logger_class.write "#{text}\n"
          when :puts
            io_or_logger_class.puts text
          when :info
            io_or_logger_class.info text
          when :debug
            io_or_logger_class.debug text
          when :warn
            io_or_logger_class.warn text
          when :error
            io_or_logger_class.error text
          else
            io_or_logger_class.send(log_method, text)
        end
      rescue NoMethodError => e
        unless io_or_logger_class == $stderr && write_command == :write
          self.io_or_logger_class = $stderr
          self.log_method = :write
          log "NestedLogger: Error logging to #{io_or_logger_class.inspect}. No such method '#{write_command ? write_command : 'write'}'"
          log "Switched to $stderr#write"
          log(text)
        else
          raise e
        end
      end
      #io_or_logger_class.write "#{message.to_s.indent(depth, '  ')}\n"
    end
    io_or_logger_class
  end

  def io_or_logger_class=(io_or_logger_class)
    @io_or_logger_class = io_or_logger_class || $stdout
  end

end
