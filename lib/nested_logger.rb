require 'nested_logger/version'
require 'nested_logger/tracer'

module NestedLogger

  def lv(name)
    NestedLogger.lv(name)
  end

  def log_nested(*messages)
    NestedLogger.log(*messages)
  end

  def nested_logger
    NestedLogger
  end

  def with_tracing(&block)
    NestedLogger.with_tracing(&block)
  end

  def without_tracing(&block)
    NestedLogger.without_tracing(&block)
  end

  def self.ignore(group)
    without_tracing { tracer.ignore group }
  end

  def self.ignore_bundler
    without_tracing { ignore 'bundler' }
  end

  def self.ignore_class(class_or_name)
    without_tracing { tracer.ignore_class class_or_name }
  end

  def self.ignore_class_group(name)
    without_tracing { tracer.ignore_class_group(name) }
  end

  def self.ignore_core
    without_tracing { ignore 'core' }
  end

  def self.ignore_defaults
    ignore_core
    ignore_stdlib
    ignore_irb
    ignore_bundler
  end

  def self.ignore_file_group(name)
    without_tracing { tracer.ignore_file_group(name) }
  end

  def self.ignore_gem(name)
    without_tracing { tracer.ignore_gem name }
  end

  def self.ignore_irb
    without_tracing { ignore 'irb' }
  end

  def self.ignore_rails
    without_tracing { ignore 'rails' }
  end

  def self.ignore_stdlib
    without_tracing { ignore 'stdlib' }
  end

  def self.log(*messages)
    without_tracing { tracer.log(*messages) }
  end

  def self.log_to(io_or_logger_class)
    tracer.log_to io_or_logger_class
  end

  def self.log_method=(method_name)
    tracer.log_method = method_name
  end

  def self.lv(name)
    without_tracing do
      name = name.to_s.to_sym
      parent = tracer.uplevel(nil, 0)
      begin
        log "#{name} => #{parent.variable(name).inspect}"
      rescue NameError
        log "#{name} => <UNDEFINED>"
      end
    end
  end

  def self.prefix
    tracer.prefix
  end

  def self.prefix?
    tracer.prefix?
  end

  def self.prefix=(line_or_class_symbol)
    tracer.prefix = line_or_class_symbol
  end

  def self.start
    tracer.start
  end

  def self.stop
    tracer.stop
  end

  def self.with_tracing(&block)
    turn_back_off = tracer.off?
    tracer.on
    begin
      yield
    ensure
      tracer.off if turn_back_off
    end
  end

  def self.without_tracing(&block)
    turn_back_on = tracer.on?
    tracer.off
    begin
      yield
    ensure
      tracer.on if turn_back_on
    end
  end

  class << self
    protected

    def tracer
      @tracer ||= NestedLogger::Tracer.new
    end

  end

end

ENV['NESTED_LOGGER_IGNORE'].to_s.split(',').each { |item| NestedLogger.ignore item.strip }
NestedLogger.prefix = ENV['NESTED_LOGGER_PREFIX'].to_s.to_sym if ENV['NESTED_LOGGER_PREFIX']
NestedLogger.start if ENV['NESTED_LOGGER_AUTOSTART'].to_s.downcase == "true"