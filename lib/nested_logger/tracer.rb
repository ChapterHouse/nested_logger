require 'nested_logger/logger'
require 'nested_logger/binding'
require 'active_support/all'
require 'debug_inspector'

class NestedLogger::Tracer

  attr_reader :quiet, :track_missing

  def initialize

    @extractor_regex = Regexp.new('(?:#<Class:|#<Module:)?(.*?)>?$')
    @logger = NestedLogger::Logger.new
    @missed_classes = []
    @method_regex = Regexp.new('\.*([\w,_]*)(\(.*?\))(.*)')
    @name_regex = Regexp.new('(?:#<)?(.*?)(?:\:0x.*)?$')
    @quiet = false

    @skip_bindings = ['RubyVM::DebugInspector', 'NestedLogger', 'NestedLogger::Tracer', 'NestedLogger:Logger', 'Kernel']
    @skip_classes = [nil, '', 'RubyVM::DebugInspector', 'NestedLogger', 'NestedLogger::Tracer', 'NestedLogger:Logger', 'nil']

    @sourced_file = {}

    @trace_point ||= TracePoint.new { |tp| parse_trace(tp) }
    @track_missing = false

  end

  def ignore(group)
    File.open(File.join(File.dirname(__FILE__), '..', 'class_groups', group.to_s), 'r') do |file|
      file.each_line { |name| skip_class(name) unless name[0] == '#' }
    end
  end

  def log(*messages)
    messages.each { |message| logger.log(message) unless message.blank? }
  end

  def missing_only=(x)
    @missing_only = !!x
  end

  def quiet=(x)
    @quiet = !!x
  end

  def skip_class(klass_name)
    skip_classes << klass_name.strip
    skip_classes.uniq!
  end

  def start
    trace_point.enable
  end
  alias :on :start

  def stop
    trace_point.disable
  end
  alias :off :stop

  def started?
    trace_point.enabled?
  end
  alias on? :started?

  def stopped?
    !trace_point.enabled?
  end
  alias :off? :stopped?

  def toggle
    off? ? on : off
  end

  def uplevel(string=nil, n=1)
    n = n.to_i
    n = 0 if n < 0
    i = -1
    binding = RubyVM::DebugInspector.open do |vm|
      while n >= 0
        i += 1
        begin
          frame_extracted = extracted_name(vm.frame_class(i))
          while skip_bindings.include?(frame_extracted)
            i += 1
            frame_extracted = extracted_name(vm.frame_class(i))
          end
          n -= 1
        rescue ArgumentError => e
          location = File.expand_path(__FILE__)
          backtrace = e.backtrace.select { |line| File.expand_path(/(.*?):/.match(line)[1]) != location }
          e.set_backtrace(backtrace)
          raise e
        end
      end
      vm.frame_binding(i)
    end

    begin
      string ? binding.send(:eval, string) : binding
    rescue Exception => e
      location = File.expand_path(__FILE__)
      backtrace = e.backtrace.select { |line| File.expand_path(/(.*?):/.match(line)[1]) != location }
      e.set_backtrace(backtrace)
      raise e
    end
  end

  private

  attr_reader :extractor_regex, :trace_point, :last_location, :logger, :method_regex, :missed_classes, :name_regex, :skip_bindings, :skip_classes, :sourced_file

  def extracted_name(klass)
    klass_name = klass.inspect
    sub_name = extractor_regex.match(klass_name)[1]
    while sub_name != klass_name
      klass_name = sub_name
      sub_name = extractor_regex.match(klass_name)[1]
    end
    name_regex.match(klass_name)[1].strip
  end

  def last_location=(tp)
    @last_location = [tp.path, tp.lineno]
  end

  def log_locals(tp)
    locals = tp.binding.locals
    locals.each_key { |key| log "#{key} => #{locals[key].inspect}" }
  end

  def log_source(tp, postfix=nil)
    unless source_logged?(tp)
      log(source_code(tp) + postfix.to_s)
      self.last_location = tp
    end
  end

  def parse_trace(tp)

    if track_missing && !skipped?(tp)
      klass_name = extracted_name(tp.defined_class)
      unless missed_classes.include?(klass_name)
        $stdout.write("Missed: #{klass_name.inspect}\n")
        missed_classes << klass_name
      end
    end

    unless quiet || skipped?(tp)

      old_quiet = quiet
      self.quiet = true

      case tp.event
        when :line
          @exception = nil
          source = source_code(tp)
          log_source(tp) unless source.starts_with?('NestedLogger.') || source.starts_with?('lv ') || source.starts_with?('lv(')
        when :call

          if tp.defined_class.name
            prefix = "#{tp.defined_class.name}#"
          else
            match = tp.defined_class.inspect.match(/:.*?>/)
            prefix = match ? "#{match[0][1..-2]}." : tp.defined_class.inspect
          end

          method_name = prefix + tp.method_id.to_s

          match = method_regex.match(source_code(tp))

          if match
            parameters = match[2]
            comments = match[3]
          else
            parameters = nil
            comments = nil
          end

          logger.depth += 1
          log "def #{method_name}#{parameters}#{comments}"
          logger.depth += 1
          log_locals(tp)
        when :return
          logger.depth -= 1
          @exception ? log_source(tp," -> #{tp.return_value.inspect}") : log("end -> #{@exception.inspect}")
          logger.depth -= 1
        when :raise
          @exception = tp.raised_exception
          log_source(tp," -> #{tp.raised_exception.inspect}")
        when :b_call
          logger.depth += 1
          log_source(tp)
          logger.depth += 1
        when :b_return
          logger.depth -= 1
          @exception ? log_source(tp," -> #{tp.return_value.inspect}") : log("end -> #{@exception.inspect}")
          logger.depth -= 1
        when :c_call
          logger.depth += 1
          log_source(tp)
          logger.depth += 1
        #log_locals(tp)
        when :c_return
          logger.depth -= 1
          @exception ? log_source(tp," -> #{tp.return_value.inspect}") : log("end -> #{@exception.inspect}")
          logger.depth -= 1
        when :class
          logger.depth += 1
          log_source(tp)
        #logger.depth += 1
        when :end
          logger.depth -= 1
          log_source(tp)
          logger.depth -= 1
        else
          unknown_tp(tp)
      end

      self.quiet = old_quiet

    else
      klass_name = extracted_name(tp.defined_class)
      if klass_name == "PeopleController"
        $stdout.write("No data for #{klass_name} #{tp.defined_class.inspect} #{missing_only} #{quiet} #{skipped?(tp.defined_class)}\n")
      end
    end

  end

  def skipped?(tp)
    klass = tp.defined_class
    klass_name = extracted_name(klass)
    !tp.defined_class.nil? && (skip_classes.include?(klass_name) || klass_name.starts_with?("0x0"))
  end

  def source_code(tp)
    traced_file(tp.path)[tp.lineno-1].to_s.strip
  end

  def source_logged?(tp)
    last_location == [tp.path, tp.lineno] #&& tp.event != :raise
  end

  def traced_file(path)
    sourced_file[path] ||= File.readlines(path).map(&:chomp) rescue []
  end

  def unknown_tp(tp)
    commands = %i{ binding defined_class event lineno method_id path raised_exception return_value }
    #commands = [:binding, :defined_class, :event, :lineno, :method_id, :path, :raised_exception, :return_value]

    puts "Unknown event #{tp.event.inspect}"
    commands.each do |command|
      x = tp.send(command) rescue 'N/A'
      puts "  #{command}: #{x.inspect}"
    end

  end


end
