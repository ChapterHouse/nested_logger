require 'nested_logger/logger'
require 'nested_logger/binding'
require 'set'
require 'active_support/all'
require 'pathname'
require 'debug_inspector'

class NestedLogger::Tracer

  attr_reader :filter, :quiet
  attr_accessor :prefix

  def initialize

    @extractor_regex = Regexp.new('(?:#<Class:|#<Module:)?(.*?)>?$')

    @included_classes = [].to_set


    @logger = NestedLogger::Logger.new
    @missed_classes = []
    @method_regex = Regexp.new('\.*([\w,_]*)(\(.*?\))(.*)')
    @name_regex = Regexp.new('(?:#<)?(.*?)(?:\:0x.*)?$')

    @filter = :exclusive
    @prefix = false
    @quiet = false

    @skip_bindings = ['RubyVM::DebugInspector', 'NestedLogger', 'NestedLogger::Tracer', 'NestedLogger:Logger', 'Kernel'].to_set
    @skip_classes = [nil, '', 'RubyVM::DebugInspector', 'NestedLogger', 'NestedLogger::Tracer', 'NestedLogger:Logger', 'nil'].to_set
    @skip_files = [].to_set
    @skip_directories = [].to_set

    @sourced_file = {}

    @trace_point ||= TracePoint.new { |tp| parse_trace(tp) }

  end

  def filter=(style)
    style = style.to_s.to_sym
    if style != :include || style != :exclude
      $stderr.write "Invalid filter style #{style}. Value must be either :include or :exclude\n"
    else
      @filter = style
    end
    @filter
  end

  def ignore_gem(name, skip_dependencies=true)
    begin
      spec = Gem::Specification.find_by_name(name)
    rescue Gem::LoadError
      raise ArgumentError.new("Could not locate #{name.ispect} gem")
    end

    seen = [spec.name]

    skip_directory spec.gem_dir

    if skip_dependencies
      dependencies = spec.dependencies
      until dependencies.empty?
        begin
          spec = dependencies.shift.to_spec
          unless seen.include?(spec.name)
            seen << spec.name
            skip_directory spec.gem_dir
            dependencies += spec.dependencies.flatten
          end
        rescue Gem::LoadError
        end
      end
    end

  end

  def ignore(class_or_group)
    if class_or_group.is_a?(Module)
      ignore_class class_or_group
    else
      begin

        ignore_class_group class_or_group
      rescue Errno::ENOENT
        ignore_class class_or_group
      else
        ignore_file_group class_or_group
      end
    end
  end

  def ignore_class(class_or_name)
    if class_or_name.is_a?(Module)
      klass = class_or_name
      class_name = klass.name
    else
      class_name = class_or_name.to_s.strip
      # Do the check first so we don't trigger the auto constant loading of Rails.
      klass = Object.const_defined?(class_name) ? Object.const_get(class_name) : nil rescue nil
    end
    initialize_class_accessor(klass, true) if klass
    skip_classes << class_name
  end

  def ignore_class_group(group)
    group_file(group, 'class').each_line { |name| ignore_class(name) unless name[0] == '#' }
  end

  def ignore_file_group(group)
    group_file(group, 'file').each_line { |name| skip_file(name) unless name[0] == '#' }
  end

  def log(*messages)
    messages.each { |message| logger.log(message) unless message.blank? }
  end

  def log_to(io_or_logger_class)
    logger.io_or_logger_class = io_or_logger_class
  end

  def log_method=(method_name)
    logger.log_method = method_name
  end

  def prefix?
    !!@prefix
  end

  def quiet=(x)
    @quiet = !!x
  end

  def skip_directory(directory_name)
    skip_directories << directory_name.strip
  end

  def skip_file(file_name)
    skip_files << file_name.strip
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

  attr_reader :extractor_regex, :trace_point, :last_location, :logger, :method_regex, :missed_classes,
              :name_regex, :skip_bindings, :skip_classes, :skip_directories, :skip_files, :sourced_file,
              :included_classes

  def class_skipped?(tp)
    if tp.defined_class != Object
      if tp.defined_class.nil?
        if tp.event == :line
          source = source_code(tp)
          source.starts_with?('def ') || source.starts_with?('module ') || source.starts_with?('class ') || source.starts_with?('include ')
        else
          true
        end
      else
        initialize_class_accessor(tp.defined_class) if !tp.defined_class.respond_to?(:nested_logger_skip) || tp.defined_class.nested_logger_skip.nil?
        tp.defined_class.nested_logger_skip
      end
    end
  end

  def initialize_class_accessor(klass, initial_value=nil)
    class << klass
      attr_accessor :nested_logger_skip
    end
    if initial_value.nil?
      klass_name = extracted_name(klass)
      initial_value = klass_name.starts_with?("0x0") || skip_classes.include?(klass_name)
    end
    klass.nested_logger_skip = initial_value
  end

  def directory_skipped?(tp)
    skip_directories.find { |name| tp.path.starts_with?(name) }
  end

  def extracted_name(klass)
    klass_name = klass.inspect
    sub_name = extractor_regex.match(klass_name)[1]
    while sub_name != klass_name
      klass_name = sub_name
      sub_name = extractor_regex.match(klass_name)[1]
    end
    name_regex.match(klass_name)[1].strip
  end

  def file_skipped?(tp)
    skip_files.find { |name| tp.path.ends_with?(name) }
  end

  def group_file(group, group_type)
    group_file = Pathname.new(group.to_s)
    unless group_file.exist?
      group_file = Pathname.new(__FILE__).dirname.parent + "#{group_type}_groups" + group_file
      raise Errno::ENOENT.new(group) unless group_file.exist?
    end
    group_file
  end

  def last_location=(tp)
    @last_location = [tp.path, tp.lineno]
  end

  def log_locals(tp)
    locals = tp.binding.locals
    locals.each_key { |key|
    log "#{log_prefix(tp)}#{key} => #{locals[key].inspect}" }
  end

  def local_code?(tp)
    tp.path.start_with?(local_path)
  end

  def local_path
    File.expand_path(Dir.pwd)
  end

  def log_prefix(tp)
    if prefix?
      if prefix == :class
        pfx = tp.defined_class ? tp.defined_class.inspect : ''
      else
        pfx = "#{local_code?(tp) ? tp.path[local_path.size+1..-1]: tp.path}:#{tp.lineno}"
      end
      # Your here, improving this and working on the inclusion principal

      '%-60s |' % [pfx]

      #logger.logger.write '%-35s %-10s: %-10s |' % ["#{path}:#{tp.lineno.to_s}", tp.defined_class.inspect[0..10], tp.event]
    end
  end

  def log_return(tp)
    unless @exception
      log_source tp, :post => " -> #{tp.return_value.inspect}", :depth => -1
    else
      logger.depth -= 1
      log "#{log_prefix(tp)}end -> #{@exception.inspect}"
      logger.depth -= 1
    end
  end

  def log_source(tp, options={})
    depth = options[:depth].to_i
    logger.depth += depth
    unless source_logged?(tp) && tp.event != :class
      log("#{log_prefix(tp)}#{source_code(tp)}#{options[:post].to_s}")
      self.last_location = tp
    end
    logger.depth += depth
  end

  def parse_trace(tp)

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
          log "#{log_prefix(tp)}def #{method_name}#{parameters}#{comments}"
          logger.depth += 1
          log_locals(tp)
        when :return
          log_return(tp)
        when :raise
          @exception = tp.raised_exception
          log_source tp, :post => " -> #{tp.raised_exception.inspect}"
        when :b_call
          log_source tp, :depth => 1
        when :b_return
          log_return tp
        when :c_call
          #log_source tp, :depth => 1
        #log_locals(tp)
        when :c_return
          #log_return tp
        when :class

        #  logger.depth += 1
        #  log_source tp
        ##logger.depth += 1
        when :end
          log_source tp, :depth => -1
        else
          unknown_tp(tp)
      end

      self.quiet = old_quiet

    end

  end

  def skipped?(tp)
    class_skipped?(tp) || file_skipped?(tp) || directory_skipped?(tp)
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
