class Binding

  def class_variable(name)
    name = name.to_s.strip
    name.prepend('@@') unless name[0..1] == '@@'
    raise NameError.new("undefined class variable `#{name}' for #{eval('inspect')}") unless class_variable?(name)
    eval(name)
  end

  def class_variable?(name)
    name = name.to_s.strip
    name.prepend('@@') unless name[0..1] == '@@'
    eval("defined?(#{name}) == 'class variable'")
  end

  def global_variable(name)
    name = name.to_s.strip
    name.prepend('$') unless name[0] == '$'
    raise NameError.new("undefined global variable `#{name}' for #{eval('inspect')}") unless global_variable?(name)
    eval(name)
  end

  def global_variable?(name)
    name = name.to_s.strip
    name.prepend('$') unless name[0] == '$'
    eval("defined?(#{name}) == 'global-variable'")
  end

  def instance_variable(name)
    name = name.to_s.strip
    name.prepend('@') unless name[0] == '@'
    raise NameError.new("undefined instance variable `#{name}' for #{eval('inspect')}") unless instance_variable?(name)
    eval(name)
  end

  def instance_variable?(name)
    name = name.to_s.strip
    name.prepend('@') unless name[0] == '@'
    eval("defined?(#{name}) == 'instance-variable'")
  end

  def local_variable?(name)
    eval("defined?(#{name}) == 'local-variable'")
  end

  def locals
    begin
      eval 'Hash[eval(("[" + local_variables.map { |x| "[#{x.inspect}, #{x}]" }.join(",") + "]"))]'
    rescue Exception => e
      {:error_acquiring_locals => e}
    end
  end


  def method(name)

  end

  def method?(name)

  end

  def variable(name)
    name = name.to_s.strip
    raise NameError.new("undefined local variable `#{name}' for #{eval('inspect')}") unless variable?(name)
    eval(name)
  end

  def variable?(name)
    name = name.to_s.strip
    eval("['local-variable', 'instance-variable', 'class variable', 'global-variable'].include?(defined?(#{name}))")
  end




end