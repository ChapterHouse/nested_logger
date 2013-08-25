def list_all(klass, depth=0)
  @seenit = [] if depth == 0
  unless @seenit.include?(klass)
    @seenit << klass
    subs = klass.constants.select do |c|
      begin
        klass.const_get(c).is_a?(Module) && klass.const_defined?(c, false)
      rescue LoadError, NameError, ArgumentError
        nil
      end
    end.compact
    subs.each { |x| list_all(klass.const_get(x), depth + 1) }
  end
  if depth == 0
    @seenit.map { |x| x.name }.compact.sort
  end
end


def clean_module_array(array_of_modules)
  array_of_modules.flatten!
  array_of_modules.compact!
  array_of_modules.delete_if { |x| x.respond_to?(:name) && x.name.nil? }
  array_of_modules.sort! { |a, b| (a.respond_to?(:name) && b.respond_to?(:name)) ? a.name <=> b.name : a <=> b }
  array_of_modules.uniq!
end


a = list_all(Object)
b = a.map { |x| list_all(Object.const_get(x)) }
clean_module_array(b)
puts a == b
puts b - a
exit

puts 'Recording known Modules.'
known_modules = []
ObjectSpace.each_object(Module) { |x| known_modules << x if x.is_a?(Module) }
clean_module_array(known_modules)
known_modules.map! { |x| list_all(x) }
clean_module_array(known_modules)


#known_modules.map! { |x| x.name.sub('.class', '') }
known_modules.delete('Complex::compatible')
known_modules.delete('NameError::message')
known_modules.delete('Rational::compatible')
known_modules.delete('ARGF.class')
known_modules.delete('Addrinfo')
known_modules.delete('BasicSocket')
known_modules.unshift 'ARGF'
clean_module_array(known_modules)




#File.open('baseline', 'w') { |f| Marshal.dump(known_modules, f) }
File.open('baseline.txt', 'w') { |f| f.puts known_modules.join("\n") }



