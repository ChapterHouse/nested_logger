\def list_all(klass, depth=0)
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
  #puts "clean_module_array(#{array_of_modules.inspect})"
  array_of_modules.flatten!
  array_of_modules.compact!
  array_of_modules.delete_if { |x| x.respond_to?(:name) && x.name.nil? }
  array_of_modules.sort! { |a, b| a.inspect <=> b.inspect }
  array_of_modules.uniq!
end

#libs = ['bundler']
libs = []

puts "Loading core_pure Modules."
known_modules = File.readlines('lib/class_groups/core_pure').delete_if { |x| x[0] == '#' }.map { |x| Object.const_get(x.strip) }

puts 'Requiring libraries.'
libs.each do |lib|
  puts lib
  require lib
end

new_modules =[]
puts 'Identifying new Modules.'
ObjectSpace.each_object(Module) do |x|
  if x.is_a?(Module) && x.inspect[0] != '#' && x != ARGF && x.inspect != 'ARGF.class'
    if !known_modules.include?(x)
      new_modules << x
    end
    known_modules << x
    #clean_module_array(known_modules)
  end
end

clean_module_array(known_modules)
clean_module_array(new_modules)
puts "#{new_modules.size} new modules found."

puts 'Traversing new modules.'
full_list = new_modules.dup
full_list.map! { |x| list_all(x) }
clean_module_array(full_list)
puts "#{full_list.size} total new modules found."

puts "Saving."
File.open('new_modules.txt', 'w') { |f| f.puts full_list.join("\n") }
#File.open('known_modules.txt', 'w') { |f| f.puts known_modules.map { |x| x.inspect }.join("\n") }
