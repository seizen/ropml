require 'libxml'

class Div < LibXML::XML::Node
  def initialize(opt=nil)
    super('div')
    case opt
    when Hash
      opt.each_pair{|k,v|self[k.to_s]=v}
    end
  end
  def text=(s)
    self<<LibXML::XML::Node.new_text(s)
  end
end
class LibXML::XML::Node #Ouline wrapping hacking
  def to_outline
    extend Outline_M
  end
end
class Outline < LibXML::XML::Node #Ouline wrapping class
  def initialize(opt=nil)
    super('outline')
    case opt
    when Hash
      opt.each_pair{|k,v|self[k.to_s]=v.to_s}
    when String
      self['text']=opt
    end
    self.to_outline
  end
end

module Outline_M #Ouline wrapping Module(containing methods)
  def next?
    n=self
    while n=n.next
      return true if n.element?
    end
    false 
  end

  def children
    a=[]; each_element{|e| a<<e.attributes.to_h if e.element?}; a
  end

  def children_with_subcount
    a=[]; each_element{|e| a<<[ e.attributes.to_h, e.children.count{|e|e.element?}, e.to_outline.next? ? '1' : '0' ] if e.element? }; a  
  end

  def outline?
    name == 'outline'
  end

  def to_cards(&block)
    p=pos
    card=Div.new({id:p+'card'})
    card['class']='card'
    say=Div.new({id:p})
    say['class']='cardsay'
    say.text=block.call(p,self['text'])
    say.output_escaping=false
    card << say
    each_element{|e| card << e.to_outline.to_cards(&block)}
    card
  end

  def pos
    r=path[11..-1].gsub(/outline|[\[\]]/,'').split('/',-1) and r.empty? ? '1' : r.map{|x|x.empty? ? '1' : x}.join('_')
  end

  def pack(n,w)
    unless w.eof
      n.times{
        s=''
        while l=w.gets
          s+=l 
          if !(c=w.getc) || c=='.'
            ol=Outline.new(s)
            nn=s.scan(/%%.*?%%/).length
            ol.pack(nn,w) if nn>0
            self << ol
            break
          else
            w.ungetc(c)
          end
        end
      }
    end
  end

  def to_s_h(opt=nil)
    h={}
    block = ->(e){
      h[e['text']]={}
      e.attributes.each{|a| h[e['text']].merge!(a.name=>a.value.force_encoding('utf-8')) unless a.name=='text'}
    }
    opt ? find(opt).each(&block) : each_element(&block)
    h
  end

  def to_h(opt=nil)
    h={}
    block = ->(e){h[e[(opt&&opt.keys[0])||'text']]=e}
    opt ? find(opt[opt.keys[0]]).each(&block) : children.each(&block)
    h
  end

  def to_a(opt=nil)
    return find(opt).to_a if opt
    a=[];each_element{|e| a<<e if e.element?};a
  end
  
  def each_config
    each_element{|e|
      a=[]
      e.each_element{|el| a<<el['text']}
      yield e['text'],a[0]
    }
  end
end

class Opml

  def initialize(s=nil)
    @doc = 
      if s 
        if s[0]=='/'
          @path=s
          LibXML::XML::Document.file(s)
        else
          LibXML::XML::Document.string(s)
        end
      else
        LibXML::XML::Document.string(<<END
<?xml version="1.0" encoding="UTF-8"?><opml version="1.0"><head><title></title><expansionState></expansionState></head><body></body></opml>
END
)  
      end
    @body=@doc.find("/opml/body")[0]
  end

  def find(*a)   #find 'string', '1',3, {k=>v} # [1] 
    if a.empty?
      root
    else
      s="/opml/body/"
      s += 
        a.map {|x| 
          case x
          when Integer
            "outline[#{x}]"
          when String
            "outline[@text=#{xpath_escape(x.to_s)}]"
          when Hash
            "outline[@#{x.keys[0]}=#{xpath_escape(x.values[0])}]"
          end
        }.join("/") 
      r=@doc.find(s)[0] and r.to_outline
    end
  end
  alias [] find

  def root
    @body.to_outline
  end

  def <<(a)
    write_a(a)
  end

  def save(p=nil)
    @doc.save(p||@path)
  end

  def to_s
    @doc.to_s
  end

  def to_h(opt=nil)
    root.to_h(opt)
  end

  def to_a(opt=nil)
    root.to_a(opt)
  end


  def rows()
    rows=[]
    @body.each_element { |x|
      h={} 
      x.attributes.each { |a|
        h.merge!({a.name=>a.value})
      }
      rows << h
    }
    rows
  end
  

  def self.db2xml
    #Ruby APIs to opml hierarchy, can be applied on an item, parent-in-the-table table too.
      opml=new
      h={}
      Klass.find_by_sql("select name, superClass as sc, included as inc from Klasses where typed = 'class' ").each{|x| h[x.name]=[x.sc,x.inc]}
      cache=[]
      h.each_pair { |k,v|
        ta=[]
        if v[0].empty?
          ta = [k]
        else
          ta += [k,v[0]]
          x=v[0]
          until h[x][0].empty?
            ta << h[x][0]
            x=h[x][0]
          end
        end
        #opml.write_a(ta.reverse+['api'])
        ta.reverse!
        opml.write_a(ta+['api'])
        Messodo.find_by_sql("select name from Methods where owner='#{ta.last}'").each {|m|
          opml.write_a(ta+['api',m.name])
        }
        h[ta.last][1].split(',').each {|z|
          opml.write_a(ta+['included',z])
          Messodo.find_by_sql("select name from Methods where owner='#{z}'").each {|m|
            opml.write_a(ta+['included',z,m.name])
          }
        }
      }
      Klass.find_by_sql("select name from Klasses where typed='module'").each {|z|
        opml.write_a ['modules',z.name]
        Messodo.find_by_sql("select name from Methods where owner='#{z.name}'").each {|m|
          opml.write_a(['modules',z.name,m.name])
        }
      }  
      Klass.find_by_sql("select name from Klasses where typed='object'").each {|z|
        opml.write_a ['objects',z.name]
        Messodo.find_by_sql("select name from Methods where owner='#{z.name}'").each {|m|
          opml.write_a(['objects',z.name,m.name])
        }
      }  
      opml.sort!
      opml.save(RAILS_ROOT+"/private/api/ruby/lib/std/rubystdlib.opml")
  end    

  def self.package(w)
    opml=new
    opml.root.pack(1,StringIO.new(w))
    opml
  end
  





    #{"1"=>[root elements], "1_1"=>[the 1st element of root,its elements], "1_2_1"=>[the 2nd element of the 1st el of root, its elements]}
  def self.packTree(r,prefix='1')
    h={}
    a=Array.new
    i=1
    r.each_element do |x|
      xh={}
      x.attributes.each { |a| xh.merge!({a.name=>a.value.force_encoding('utf-8')}) }
      a << xh
      if x.child?
        h.merge!(packTree(x,prefix+"_"+i.to_s))
      end
      i=i+1
    end
    h.merge!( { prefix => a } )
  end

    #  0              1                      2                        3...
    #[  {"1"=>[root elements]},    {"1_1"=>[],"1_2"=>[],..."2_1"=>[]...},    {"1_1_1"=>[],"1_2_1"=>[],..."2_1_1"=>[]...},  ...      ]
    def self.packLayer(e)
      layers=[]
      Opml.packTree(e).each_pair do |k,v|
        p=k.count("_")
            layers[p]={} if ! layers[p]
            layers[p].merge!({k=>v})
        end
      layers
    end

    def toTree
      @tree=Opml.packTree(@body)
    end

    def toLayers
      ls=[]
      tree.each_pair do |k,v|
        p=k.count("_")
            ls[p]={} if ! ls[p]
            ls[p].merge!({k=>v})
        end
      @layers=ls
    end
    
    def toA(r)
      a=[]
      r.each_element{|e|
        h={}
        e.attributes.each { |at| h.merge!({at.name=>at.value}) }
        h['children'] = toA(e)
        a << h
      }
      a
    end
    
    def tree
      @tree || toTree
    end

    def layers
      @layers || toLayers
    end
    
    def a
      @a ||= toA(@body)
    end
    
    
    
    
    
    
    
    def deprecated1(s)
      #@body.get_elements("//body/outline[@text='#{s}']")[0].elements[1].attributes['text']
    end

    def deprecated2(s,v)
      #@body.get_elements("//body/outline[@text='#{s}']")[0].elements[1].attributes['text']=v.to_s
      #File.open(@path, "wb") { |f| self.write(f) }
    end
    
    
    
    def plus(s)
      #i=@body.get_elements("//body/outline[@text='#{s}']")[0].elements[1].attributes['text'].to_i
      #i+=1
      #self[s]=i
    end
    
    def to_db
      xml2db_r(@body,'')
      
    end
    def xml2db_r(r,s)
      r.each_element {|e|
        v=e.attributes["text"].delete("\t")
        t = s+v+"\t"
        rec=Species.new({'name'=>t,'key'=>v})
        if e.child?
          xml2db_r(e,t)
        else
          rec.leaf=1  
        end
        rec.save
      }
    end

  
  #A\tB\tC type records => xml
  def self.db2xml_2
    opml=Opml.new
    Species.find(:all).each{|x| 
      p x.name
      opml.write_a(x.name.force_encoding('utf-8').split("\t"))
    }
    opml.save(RAILS_ROOT+"/private/wiki/rdb.opml")
    
    
  end

  #Directory to xml
  def self.dir2xml
    opml=Opml.new
    a=`find /var/w/Library/ ! \\( -path "*.AppleD*" -or -path "*:2e*" \\)`
    a.split("\n").each {|x|
      opml.write_a x[15..-1].split("/")
    }
    opml.save(RAILS_ROOT+"/private/wiki/dir.opml")
  end










  def self.sort_do(e)
    nodes=[]
    e.each_element{|x|nodes<<x}
    nodes.sort{|x,y|x.attributes['text']<=>y.attributes['text']}.each {|x|
      sort_do(x) if x.children?
      e<<x
    }
  end
  def sort!
    Opml.sort_do(@body)
  end
  def write_a(a)  
    ta=[]
    a.each {|y|
      k = Hash===y ? y[:text]||y['text'] : y
      find(*ta) << Outline.new(y) unless find(*ta,k)
      ta << k
    }
  end
  def xpath_escape(s)
    if s.include?("'")                                                          
        if s.include?('"')
        "concat('#{s.gsub(/'/,"',\"'\",'")}')"
      else
        "\"#{s}\""
      end
    else
      "'#{s}'"
    end
  end
end
