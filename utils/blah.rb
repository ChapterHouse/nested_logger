$: << File.join(__FILE__, 'lib')
require 'nested_logger'

module B

  def self.quack
    'quack'
  end

  def quack
    B.quack
  end

end

class A

  include B
  include NestedLogger

  def self.blah
    'blah'
  end

  def a(x)
    b(x + 2, 3)
  end

  def b(x, y=1) # Some comment
    z = 123
    lv(:z)
    f = '<UNDEFINED>'
    lv :q
    lv :f
    rc = x + y
  end

  def c
    self.class.blah
  end

  def d
    quack
  end

  def e
    [1, 2, 3].each { |x|
      yield x + 1
    }
  end

  def f
    begin
      g
    rescue NoMethodError
      101
    end
  end

  def g
    h
  end

  def h
    i
  end

  def i
    x = 1
    y = 2
    nil + x
    z = 3
  end

end


#NestedLogger.start

x = 1
puts 'umm'
a = A.new
a.a(1)
a.c
a.d
a.e { |b| 3 + b }
z = a.f
x + z

include NestedLogger
#
def aaa(x)
  x += 123
end

m = aaa(123)

x = caller
puts caller.inspect

aaa = 123
#puts defined?("$aaa".to_sym)
#puts defined?(:aaa)