#!/usr/bin/env ruby

require "rubygems"
require "json"
require "json-schema"
require "jsonpath"
require "erb"
require "oj"
require "rouge"
require "active_support/inflector"
require "active_support"
require "pp"

class String
  def titleize
    split(/(\W)/).map(&:capitalize).join
  end
end

class JsonParser
  def initialize root
    @json_blocks = Hash.new
    @partials = Hash.new
    @object_template = ERB.new(File.read('views/object.html.erb'))
    @page_template = ERB.new(File.read('views/page.html.erb'))
    @schema = JSON.parse(File.read('schemas/schema-04.json'))
    @root = File.basename root
    @seen = []
    @outfile = ''
  end

  def write_out file
    File.open(file, File::RDWR | File::CREAT, 0644) { |f|
      f.write @outfile
      f.flush
    }
  end

  def schemas
    @json_blocks
  end

  def highlight n, v
    return '' if v.nil?
    t = "{\"#{n}\": \"#{v}\"}"
    Rouge.highlight t, 'json', 'html'
  end

  def highlight_pattern p
    return '' if p.nil?
    Rouge.highlight "/#{p}/", "javascript", "html"
  end

  def get_binding
    binding
  end

  def render_html
    @page_template.run(get_binding {|*a| parse @json_blocks[@root]})
  end

  def pretty_json obj
    s = JSON.generate obj,
      :indent => "  ",
      :object_nl => "\n",
      :array_nl => "\n"

      formatter = Rouge::Formatters::HTML.new(css_class: 'highlight error')
      lexer = Rouge::Lexers::JSON.new
      formatter.format(lexer.lex(s))
  end

  def parse part
    html = ""
    p = {}

    parser = Proc.new do |name,attr|
      if name != "$ref"
        attr['id'] = name
      end

      if attr['patternProperties']
        attr['patternProperties'].each do |_,prop|
          ref = expand_refs prop
          if ref
            html += parse ref
          end
        end
      end
      ref = expand_refs attr
      if ref
        attr.merge! ref
        html += parse ref
      end
      p[name] = attr

      if attr['type'] == 'object'
        html += parse attr
      end
    end

    if part['definitions']
      p = part['definitions']
      p.each(&parser)
    end

    if part['properties']
      p = part['properties']
      p.each(&parser)
    end

    if part['patternProperties']
      p = part['patternProperties']
      p.each(&parser)
    end

    if part['allOf']
      part['allOf'].each do |av|
        av.each(&parser)
      end
    end

    html = @object_template.result(binding) + html

    html
  end

  def expand_refs(obj)
    r = obj["$ref"]

    if @seen.include? r
      return nil
    end

    @seen.push r

    if r.is_a?(String)
      key = File.basename r.split('#')[0]
      path = r.split('#')[1]

      if path
        path.gsub!(/\//, '.')
        STDERR.puts "Path: #{key} => #{path}"
        p = JsonPath.new path
        return (p.on @json_blocks[key])[0]
      else
        return @json_blocks[key]
      end
    end
    return nil
  end

  def add(file)
    v = Oj.load(File.read(file))
    k = File.basename(file)
    errors = JSON::Validator.fully_validate(@schema, v, :errors_as_objects => true, :version => :draft4)
    if errors == []
      @json_blocks[k] = v
    else
      puts "<h1 class=\"error\">Errors parsing #{k}</h1>"
      puts pretty_json errors
    end
  end
end

if ARGV[0] && !File.directory?(ARGV[0])
  jp = JsonParser.new ARGV[0]

  Dir.chdir(File.dirname(ARGV[0]))

  files = File.join("**", "*.json")

  Dir.glob(files).each do |f|
    if File.file?(f)
      jp.add f
    end
  end

  jp.render_html
else
  STDERR.puts "parse.rb <path_to_root_schema>"
end
