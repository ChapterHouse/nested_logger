require 'nested_logger/version'
require 'nested_logger/tracer'

module NestedLogger


  def lv(name)
    NestedLogger.without_tracing do
      name = name.to_s.to_sym
      parent = NestedLogger.tracer.uplevel(nil, 0)
      value =
      begin
        parent.variable(name)
      rescue NameError
        'UNDEFINED'
      end
      log_nested "#{name} => #{value.inspect}"
    end
  end

  def log_nested(*messages)
    NestedLogger.without_tracing { NestedLogger.tracer.log(*messages) }
  end

  def self.tracer
    @tracer ||= NestedLogger::Tracer.new
  end

  def self.missed_classes
    without_tracing { tracer.missed_classes }
  end

  def self.ignore(group)
    without_tracing { tracer.ignore group }
  end

  def self.ignore_bundler
    without_tracing { ignore 'bundler' }
  end

  def self.ignore_core
    without_tracing { ignore 'core' }
  end

  def self.ignore_irb
    without_tracing { ignore 'irb' }
  end

  def self.ignore_rails
    without_tracing { ignore 'rails' }
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



  #def self.blah
  #  RubyVM::DebugInspector.open { |dc|
  #    # backtrace locations (returns an array of Thread::Backtrace::Location objects)
  #    locs = dc.backtrace_locations
  #
  #    rc = []
  #    # you can get depth of stack frame with `locs.size'
  #    locs.each_with_index do |loc, i|
  #      # binding of i-th caller frame (returns a Binding object or nil)
  #      frame_class = dc.frame_class(i)
  #      rc << [loc, dc.frame_binding(i), frame_class] unless frame_class == self || frame_class == internal_self || frame_class == Kernel
  #    end
  #    rc
  #  }
  #
  #end

  ignore_core
  ignore_irb
  ignore_bundler
  ignore_rails
  start

end

