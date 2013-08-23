class NestedLogger::Logger

  attr_reader :depth, :logger

  def initialize(io=$stdout)
    @depth = 0
    @logger = io
  end

  def depth=(new_depth)
    new_depth = new_depth.to_i
    new_depth = 0 if new_depth < 0
    @depth = new_depth
  end

  def log(*messages)
    messages.each { |message| logger.write "#{message.to_s.indent(depth, '  ')}\n" }
    logger
  end

  def logger=(io)
    @logger = io || $stdout
  end

end
