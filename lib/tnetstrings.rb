#!/usr/bin/env ruby -w

# encoding: utf-8

module TNetStrings
  def self.dump(data)
    case data
      when String then "#{data.bytesize}:#{data.bytes.pack('C*')},"
      when Symbol then "#{data.to_s.length}:#{data.to_s},"
      when Fixnum  then "#{data.to_s.length}:#{data.to_s}#"
      when Float then "#{data.to_s.length}:#{data.to_s}^"
      when TrueClass then "4:true!"
      when FalseClass then "5:false!"
      when NilClass then "0:~"
      when Array then dump_array(data)
      when Hash then dump_hash(data)
    else
      if data.respond_to?(:to_s)
        s = data.to_s
        "#{s.length}:#{s},"
      else
        raise "Can't serialize stuff that's '#{data.class}'."
      end
    end
  end

  def self.parse(data)
    raise "Invalid data." if data.empty?
    payload, payload_type, remain = parse_payload(data)

    value = case payload_type
      when ',' then payload
      when '#' then payload.to_i
      when '^' then payload.to_f
      when '!' then payload == 'true'
      when ']' then parse_array(payload)
      when '}' then parse_hash(payload)
      when '~'
        raise "Payload must be 0 length for null." unless payload.length == 0
        nil
      else
        raise "Invalid payload type: #{payload_type}"
    end

    [ value, remain ]
  end

  def self.parse_payload(data)
    raise "Invalid payload type: #{payload_type}" if data.empty?

    len, extra = data.split(':', 2)
    len = len.to_i
    if len == 0
      payload = ''
    else
      payload, extra = extra.byteslice(0..len-1), extra.byteslice(len..-1)
    end
    payload_type, remain = extra[0], extra[1..-1]

    [ payload, payload_type, remain ]
  end

  private

  def self.parse_array(data)
    arr = []
    return arr if data.empty?

    begin
      value, data = parse(data)
      arr << value
    end while not data.empty?

    arr
  end

  def self.parse_pair(data)
    key, extra = parse(data)
    raise "Unbalanced hash" if extra.empty?
    value, extra = parse(extra)

    [ key, value, extra ]
  end

  def self.parse_hash(data)
    hsh = {}
    return hsh if data.empty?

    begin
      key, value, data = parse_pair(data)
      hsh[key.to_sym] = value
    end while not data.empty?

    hsh
  end

  def self.dump_array(data)
    payload = ""
    data.each { |v| payload << dump(v) }
    "#{payload.length}:#{payload}]"
  end

  def self.dump_hash(data)
    payload = ""
    data.each do |k,v|
      payload << dump(k.to_s)
      payload << dump(v)
    end
    "#{payload.length}:#{payload}}"
  end
end

if $0 == __FILE__
  require 'minitest/autorun'

  class NmsgTestSocket < MiniTest::Unit::TestCase

    def test_parse_string
      n = "3:foo,"

      s, r = TNetStrings::parse(n)
      assert_equal "foo", s
      assert_equal "", r
    end

    def test_parse_strings
      n = "3:foo,3:bar,6:foobar,"

      s, r = TNetStrings::parse(n)
      assert_equal "foo", s
      assert_equal "3:bar,6:foobar,", r

      s, r = TNetStrings::parse(r)
      assert_equal "bar", s
      assert_equal "6:foobar,", r

      s, r = TNetStrings::parse(r)
      assert_equal "foobar", s
      assert_equal "", r
    end

    def test_parse_utf8_bytes
      n = "3:foo,2:\u00B5,4:\xf0\x9f\x98\x87,"

      s, r = TNetStrings::parse(n)
      assert_equal "foo", s
      assert_equal "2:µ,4:😇,", r

      s, r = TNetStrings::parse(r)
      assert_equal "µ", s
      assert_equal "4:\u{1F607},".force_encoding('UTF-8'), r

      s, r = TNetStrings::parse(r)
      assert_equal "😇", s
      assert_equal "", r
    end

    def test_parse_fixnum
      n = "2:42#"

      i, r = TNetStrings::parse(n)
      assert_equal 42, i
      assert_equal "", r
    end

    def test_parse_fixnums
      n = "2:42#1:7#6:123456#"

      i, r = TNetStrings::parse(n)
      assert_equal 42, i
      assert_equal "1:7#6:123456#", r

      i, r = TNetStrings::parse(r)
      assert_equal 7, i
      assert_equal "6:123456#", r

      i, r = TNetStrings::parse(r)
      assert_equal 123_456, i
      assert_equal "", r
    end

    def test_parse_float
      n = "9:3.1415926^"

      f, r = TNetStrings::parse(n)
      assert_equal 3.1415926, f
      assert_equal "", r
    end

    def test_parse_bool
      n = "4:true!"

      b, r = TNetStrings::parse(n)
      assert_equal true, b
      assert_equal "", r

      n = "5:false!"

      b, r = TNetStrings::parse(n)
      assert_equal false, b
      assert_equal "", r
    end

    def test_parse_nil
      n = "0:~"

      v, r = TNetStrings::parse(n)
      assert_equal nil, v
      assert_equal "", r
    end

    def test_parse_mixed
      n = "2:ok,4:true!3:313#"

      v, r = TNetStrings::parse(n)
      assert_equal "ok", v
      assert_equal "4:true!3:313#", r

      v, r = TNetStrings::parse(r)
      assert_equal true, v
      assert_equal "3:313#", r

      v, r = TNetStrings::parse(r)
      assert_equal 313, v
      assert_equal "", r
    end

    def test_parse_array
      s, r = TNetStrings::parse("0:]")
      assert_equal [], s
      assert_equal "", r

      s, r = TNetStrings::parse("18:3:foo,3:bar,3:baz,]")
      assert_equal [ "foo", "bar", "baz" ], s
      assert_equal "", r

      a = "0:]18:3:foo,3:bar,3:baz,]37:5:false!6:3.1415^2:42#0:~4:true!2:ok,]"
      s, r = TNetStrings::parse(a)
      assert_equal [], s
      assert_equal "18:3:foo,3:bar,3:baz,]37:5:false!6:3.1415^2:42#0:~4:true!2:ok,]", r

      s, r = TNetStrings::parse(r)
      assert_equal [ "foo", "bar", "baz" ], s
      assert_equal "37:5:false!6:3.1415^2:42#0:~4:true!2:ok,]", r

      s, r = TNetStrings::parse(r)
      assert_equal [ false, 3.1415, 42, nil, true, "ok" ], s
      assert_equal "", r
    end

    def test_parse_hash
      h, r = TNetStrings::parse("0:}")
      assert_equal Hash.new, h
      assert_equal "", r

      h, r = TNetStrings::parse("12:3:foo,3:bar,}")
      assert_equal({foo: "bar"}, h)
      assert_equal "", r

      n = "26:3:cat,4:meow,3:dog,4:bark,}12:3:cow,3:moo,}"
      h, r = TNetStrings::parse(n)
      assert_equal({ cat: "meow", dog: "bark" }, h)
      assert_equal "12:3:cow,3:moo,}", r

      h, r = TNetStrings::parse(r)
      assert_equal({ cow: "moo" }, h)
      assert_equal "", r
    end

    def test_parse_exceeding
      s = "3:foo,4:true!"

      v, r = TNetStrings::parse(s)
      assert_equal "foo", v
      assert_equal "4:true!", r

      v, r = TNetStrings::parse(r)
      assert_equal true, v
      assert_equal "", r

      msg = ""
      begin
        v, r = TNetStrings::parse(r)
      rescue => e
        msg = e.message
      end
      assert_equal "Invalid data.", msg
      assert_equal "", r
    end

    def test_dump_strings
      s = TNetStrings::dump("foobar")
      assert_equal "6:foobar,", s

      s << TNetStrings::dump("baz")
      assert_equal "6:foobar,3:baz,", s
    end

    def test_dump_byte_strings
      s = TNetStrings::dump("ßöö")
      assert_equal "6:\xC3\x9F\xC3\xB6\xC3\xB6,".unpack('C*'), s.bytes

      s << TNetStrings::dump("µ")
      assert_equal "6:ßöö,2:µ,", s.force_encoding("UTF-8")

      s << TNetStrings::dump("\u{1F607}").force_encoding('UTF-8')
      assert_equal "6:ßöö,2:µ,4:😇,", s.force_encoding("UTF-8")
    end

    def test_dump_symbol
      s = TNetStrings::dump(:foobarbaz)
      assert_equal "9:foobarbaz,", s
    end

    def test_dump_fixnums
      s = TNetStrings::dump(65_537)
      assert_equal "5:65537#", s

      s << TNetStrings::dump(42)
      assert_equal "5:65537#2:42#", s

      s << TNetStrings::dump(300_000_000)
      assert_equal "5:65537#2:42#9:300000000#", s
    end

    def test_dump_floats
      s = TNetStrings::dump(3.1415926)
      assert_equal "9:3.1415926^", s

      s << TNetStrings::dump(0.0000000000667)
      assert_equal "9:3.1415926^8:6.67e-11^", s
    end

    def test_dump_bool
      s = TNetStrings::dump(false)
      assert_equal "5:false!", s

      s << TNetStrings::dump(true)
      assert_equal "5:false!4:true!", s
    end

    def test_dump_nil
      s = TNetStrings::dump(nil)
      assert_equal "0:~", s
    end

    def test_dump_array
      s = TNetStrings::dump([])
      assert_equal "0:]", s

      s << TNetStrings::dump([ "foo", "bar", "baz" ])
      assert_equal "0:]18:3:foo,3:bar,3:baz,]", s

      s << TNetStrings::dump([ false, 3.1415, 42, nil, true, "ok" ])
      assert_equal "0:]18:3:foo,3:bar,3:baz,]37:5:false!6:3.1415^2:42#0:~4:true!2:ok,]", s
    end

    def test_dump_hash
      s = TNetStrings::dump({})
      assert_equal "0:}", s

      s << TNetStrings::dump({ foo: "bar"})
      assert_equal "0:}12:3:foo,3:bar,}", s
    end
  end
end
