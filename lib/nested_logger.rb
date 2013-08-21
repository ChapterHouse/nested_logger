#require "nested_logger/version"
#require 'yaml'

require 'active_support/all'
#require 'active_support/core_ext/big_decimal/conversions'


require 'debug_inspector'
#require 'tracepoint'

module NestedLogger

  ExtractorRegex = Regexp.new('(?:#<Class:|#<Module:)?(.*?)>?$')
  NameRegex = Regexp.new('(?:#<)?(.*?)(?:\:0x.*)?$')

  def self.start
    trace_point.enable
  end

  def self.stop
    trace_point.disable
  end

  def lv(name)
    name = name.to_sym
    NestedLogger.quiet = true
    value = NestedLogger.parent_variable_defined?(name) ? NestedLogger.parent_variable_get(name) : 'UNDEFINED'
    NestedLogger.quiet = false
    nested_log "#{name} => #{value.inspect}"
  end

  def nested_log(*messages)
    NestedLogger.nested_log(*messages)
  end

  private

  SourcedFile = {}

  def self.depth
    Thread.current[:NestedLoggerDepth] ||= 0
  end

  def self.depth=(x)
    x = x.to_i
    x = 0 if x < 0
    Thread.current[:NestedLoggerDepth] = x
  end

  def self.ignore(group)
    File.open(File.join(File.dirname(__FILE__), 'class_groups', group.to_s), 'r') do |file|
      file.each_line { |name| skip_class(name) }
    end
  end

  def self.ignore_bundler
    ignore 'bundler'
  end

  def self.ignore_core
    ignore 'core'
  end

  def self.ignore_irb
    ignore 'irb'
  end

  def self.ignore_rails
    ignore 'rails'
  end

  def self.internal_self
    @internal_self ||= class << self; self; end
  end

  def self.log_source(tp, postfix=nil)
    nested_log(source_code(tp) + postfix.to_s)
  end

  def self.nested_log(*messages)
    messages.each do |message|
      $stdout.write message.to_s.indent(NestedLogger.depth, '  ') + "\n"
      #puts message.indent(NestedLogger.depth, '  ')
    end
  end

  def self.parent_binding
    RubyVM::DebugInspector.open { |vm| vm.frame_binding(4) }
  end

  def self.parent_variable_defined?(symbol)
    parent_binding.eval("['local-variable', 'instance-variable', 'class variable'].include?(defined?(#{symbol}))")
  end

  def self.parent_variable_get(symbol)
    parent_binding.eval(symbol.to_s)
  end

  def self.quiet
    @quiet ||= false
  end

  def self.quiet=(x)
    @quiet = !!x
  end

  def self.uplevel(string, n=1)
    n = n.to_i
    n = 0 if n < 0
    i = -1
    binding = RubyVM::DebugInspector.open do |vm|
      while n >= 0
        i += 1
        frame_extracted = extracted_name(vm.frame_class(i))
        self_extracted = extracted_name(self)
        rvmdi_extracted = extracted_name(RubyVM::DebugInspector)
        kernel_extracted = extracted_name(Kernel)
        while frame_extracted == self_extracted || frame_extracted == rvmdi_extracted || frame_extracted == kernel_extracted
          i += 1
          frame_extracted = extracted_name(vm.frame_class(i))
        end
        n -= 1
      end
      #puts "Translated to #{i} with #{vm.frame_class(i).inspect} / #{extracted_name(vm.frame_class(i))} versus #{self.inspect} / #{internal_self.inspect}"
      vm.frame_binding(i)
    end
    begin
      binding.send(:eval, string)
    rescue => e
      location = File.expand_path(__FILE__)
      backtrace = e.backtrace.select { |line| File.expand_path(/(.*?):/.match(line)[1]) != location }
      e.set_backtrace(backtrace)
      raise e
    end
  end

  def self.blah
    RubyVM::DebugInspector.open { |dc|
      # backtrace locations (returns an array of Thread::Backtrace::Location objects)
      locs = dc.backtrace_locations

      rc = []
      # you can get depth of stack frame with `locs.size'
      locs.each_with_index do |loc, i|
        # binding of i-th caller frame (returns a Binding object or nil)
        frame_class = dc.frame_class(i)
        rc << [loc, dc.frame_binding(i), frame_class] unless frame_class == self || frame_class == internal_self || frame_class == Kernel
      end
      rc
    }

  end

  def self.missing_only
    @missing_only ||= false
  end

  def self.missing_only=(x)
    @missing_only = !!x
  end

  def self.skip_class(name)
    skipped_classes << name.strip
    skipped_classes.uniq!
  end

  def self.skipped_classes
    @skipped_classes ||= [nil, '', extracted_name(RubyVM::DebugInspector), extracted_name(self), extracted_name(nil)]
  end

  def self.source_code(tp)
    traced_file(tp.path)[tp.lineno-1].to_s.strip
  end

  def self.traced_file(path)
    SourcedFile[path] ||= File.readlines(path).map(&:chomp) rescue []
  end

  def self.missed_classes
    @missed_classes ||= []
  end

  def self.extracted_name(klass)
    name = klass.inspect
    sub_name = ExtractorRegex.match(name)[1]
    while sub_name != name
      name = sub_name
      sub_name = ExtractorRegex.match(name)[1]
    end
    NameRegex.match(name)[1].strip
  end

  def self.skipped?(klass)
    klass_name = extracted_name(klass)
    skipped_classes.include?(klass_name) || klass_name.starts_with?("0x0")
  end

  def self.trace_point

    @last_position ||= []
    #@tp ||= TracePoint.trace do |tp|
    @trace_point ||= TracePoint.new do |tp|
    #(:line, :call, :return, :raise, :b_call, :b_return) do |tp|
      if !skipped?(tp.defined_class)
        klass_name = extracted_name(tp.defined_class)
        unless missed_classes.include?(klass_name)
          $stdout.write("Missed: #{klass_name.inspect}\n")
          missed_classes << klass_name
        end
      end

      unless missing_only || quiet || skipped?(tp.defined_class)

        old_quiet = quiet
        self.quiet = true

        case tp.event
          when :line
            source = source_code(tp).strip
            log_source(tp) unless source.starts_with?('NestedLogger.stop') || source.starts_with?('lv ') || source.starts_with?('lv(')
          when :call

            if tp.defined_class.name
              prefix = "#{tp.defined_class.name}#"
            else
              match = tp.defined_class.inspect.match(/:.*?>/)
              if match
                prefix = "#{match[0][1..-2]}."
              else
                prefix = tp.defined_class.inspect
              end
            end

            method_name = prefix + tp.method_id.to_s

            method_regexp = Regexp.new('\.*([\w,_]*)(\(.*?\))(.*)')
            match = method_regexp.match(source_code(tp))

            if match
              parameters = match[2]
              comments = match[3]
            else
              parameters = nil
              comments = nil
            end

            NestedLogger.depth += 1
            nested_log "def #{method_name}#{parameters}#{comments}"
            NestedLogger.depth += 1
            #log_source(tp, " #{prefix}#{tp.method_id}")
            if parameters
              parameters = parameters[1..-2].to_s.split(',')
              parameters.pop if parameters.last.to_s.strip.starts_with?('&')
              parameters = parameters.join(',')
              begin
                #values = tp.binding.eval("[#{parameters}]")
                #parameters.split(',').each_with_index { |parameter, i| nested_log "#{parameter.split('=').first.strip}: #{values[i].inspect}" }
              rescue SyntaxError
                $stdout.write "Syntax Error: [#{parameters}]\n"
              rescue => e
                $stdout.write "Ouch: #{e.inspect}\n"
              end
            end
          when :return
            NestedLogger.depth -= 1
            log_source(tp,"  ->  #{tp.return_value.inspect}")
            NestedLogger.depth -= 1
          when :raise
            log_source(tp,"  ->  #{tp.raised_exception.inspect}")
          when :b_call
            #nested_log("VVV")
            NestedLogger.depth += 1
            log_source(tp) unless @last_position.first == tp.path && @last_position.last == tp.lineno
            NestedLogger.depth += 1
          when :b_return
            NestedLogger.depth -= 1
            log_source(tp,"  ->  #{tp.return_value.inspect}")
            NestedLogger.depth -= 1
          else
            #unknown_tp(tp)
        end

        @last_position = [tp.path, tp.lineno]
        self.quiet = old_quiet

      else
        klass_name = extracted_name(tp.defined_class)
        if klass_name == "PeopleController"
          $stdout.write("No data for #{klass_name} #{tp.defined_class.inspect} #{missing_only} #{quiet} #{skipped?(tp.defined_class)}\n")
        end
      end

      def self.unknown_tp(tp)
        commands = %i{ binding defined_class event lineno method_id path raised_exception return_value }
        #commands = [:binding, :defined_class, :event, :lineno, :method_id, :path, :raised_exception, :return_value]

        commands.each do |command|
          begin
            x = tp.send(command)
          rescue
            x = 'N/A'
          end
          puts "#{command}: #{x.inspect}"
        end

      end


    end

  end

  ignore_core
  ignore_irb
  ignore_bundler
  ignore_rails
  start

end
