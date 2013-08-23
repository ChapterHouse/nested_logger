class Binding

  def locals
    eval 'Hash[eval(("[" + local_variables.map { |x| "[#{x.inspect}, #{x}]" }.join(",") + "]"))]'
  end

  def variable?(name)
    name = name.to_s.strip
    eval("['local-variable', 'instance-variable', 'class variable', 'global-variable'].include?(defined?(#{name}))")
  end

  def variable(name)
    name = name.to_s.strip
    raise NameError.new("undefined local variable `#{name}' for #{eval('inspect')}") unless variable?(name)
    eval(name)
  end

  def local_variable?(name)
    eval("defined?(#{name}) == 'local-variable'")
  end

  def instance_variable?(name)
    name = name.to_s.strip
    name.prepend('@') unless name[0] == '@'
    eval("defined?(#{name}) == 'instance-variable'")
  end

  def class_variable?(name)
    name = name.to_s.strip
    name.prepend('@@') unless name[0..1] == '@@'
    eval("defined?(#{name}) == 'class variable'")
  end

  def global_variable?(name)
    name = name.to_s.strip
    name.prepend('$') unless name[0] == '$'
    eval("defined?(#{name}) == 'global-variable'")
  end

end