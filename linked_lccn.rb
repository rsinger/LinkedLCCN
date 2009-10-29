require 'rubygems'
require 'sinatra'

require 'net/http'
require 'enhanced_marc'
require 'rdf_objects'
require 'isbn/tools'
include RDFObject

configure do
  Curie.add_prefixes! :mo=>"http://purl.org/ontology/mo/", :skos=>"http://www.w3.org/2004/02/skos/core#",
   :owl=>'http://www.w3.org/2002/07/owl#', :wgs84 => 'http://www.w3.org/2003/01/geo/wgs84_pos#', 
   :dcterms => 'http://purl.org/dc/terms/', :bibo => 'http://purl.org/ontology/bibo/', :rda=>"http://RDVocab.info/Elements/"
end
get '/:id' do
  marc = get_marc(params["id"])
  not_found if marc.nil?
  rdf = to_rdf(marc)
  content_type 'application/rdf+xml', :charset => 'utf-8'
  to_rdfxml(rdf)
end


def get_marc(lccn)
  uri = URI.parse "http://lccn.loc.gov/#{lccn}/marcxml"
  req = Net::HTTP::Get.new(uri.path)
  res = Net::HTTP.start(uri.host, uri.port) {|http|
    http.request(req)
  }
  return nil unless res.code == "200"
  record = nil
  marc = MARC::XMLReader.new(StringIO.new(res.body))
  marc.each {|rec| record = MARC::Record.new_from_marc(rec.to_marc)}
  record
end

def to_rdf(marc)
  id = marc['010'].value.strip
  resource = Resource.new("http://lccn.heroku.com/#{id}#i")
  resource.relate("[owl:sameAs]", "http://lccn.loc.gov/#{id}")  
  resource.assert("[bibo:lccn]", id)
  case marc.class.to_s
  when "MARC::SoundRecord" then model_sound(marc, resource)
  when "MARC::BookRecord" then model_book(marc, resource)
  when "MARC::SerialRecord" then model_serial(marc, resource)
  when "MARC::MapRecord" then model_map(marc, resource)
  when "MARC::VisualRecord" then model_visual(marc, resource)
  else model_generic(marc, resource)
  end
  marc_common(resource, marc)
  resource
end

def model_sound(marc, resource)
  resource.relate("[rdf:type]", "[mo:Recording]")
  resource
end

def model_book(marc, resource)
  if marc.is_conference?
    resource.relate("[rdf:type]","[bibo:Proceedings]")
  elsif marc.is_manuscript?
    resource.relate("[rdf:type]","[bibo:Manuscript]")
  elsif marc.nature_of_contents && marc.nature_of_contents.index("m")
    resource.relate("[rdf:type]","[bibo:Thesis]")
  elsif marc.nature_of_contents && marc.nature_of_contents.index("u")
    resource.relate("[rdf:type]","[bibo:Standard]")
  elsif marc.nature_of_contents && marc.nature_of_contents.index("j")
    resource.relate("[rdf:type]","[bibo:Patent]")    
  elsif marc.nature_of_contents && marc.nature_of_contents.index("t")
    resource.relate("[rdf:type]","[bibo:Report]")
  elsif marc.nature_of_contents && marc.nature_of_contents.index("l")
    resource.relate("[rdf:type]","[bibo:Legislation]")
  elsif marc.nature_of_contents && marc.nature_of_contents.index("v")
    resource.relate("[rdf:type]","[bibo:LegalCaseDocument]")
  elsif marc.nature_of_contents && !(marc.nature_of_contents & ["c", "d", "e", "r"]).empty?
    resource.relate("[rdf:type]","[bibo:ReferenceSource]")
  else
    resource.relate("[rdf:type]", "[bibo:Book]")
  end
  if marc.nature_of_contents
    marc.nature_of_contents(true).each do | genre |        
      resource.assert("[dcterms:type]", genre)
    end
  end
end

def model_serial(marc, resource)
  if marc.nature_of_contents
    marc.nature_of_contents(true).each do | genre |        
      resource.assert("[dcterms:type]", genre)
    end
  end
  type = marc.serial_type(true)
  if type == 'Newspaper'
    resource.relate("[rdf:type]","[bibo:Newspaper]")
  elsif type == 'Website'
    resource.relate("[rdf:type]","[bibo:Website]") 
  elsif type == 'Periodical'    
    if marc['245'].to_s =~ /\bjournal\b/i
      resource.relate("[rdf:type]","[bibo:Journal]")
    elsif marc['245'].to_s =~ /\bmagazine\b/i
      resource.relate("[rdf:type]","[bibo:Magazine]")
    else
     resource.relate("[rdf:type]","[bibo:Periodical]")
    end
  end
end

def model_map(marc, resource)
end

def model_visual(marc, resource)
  type = marc.material_type(true)
  if type == "Videorecording" or (marc['245'] && marc['245']['h'] && marc['245']['h'] =~ /videorecording/)
    resource.relate("[rdf:type]","[bibo:Film]")
  elsif type
    resource.assert("[dct:type]", type)
  end  
end

def model_generic(marc, resource)
end

def marc_common(resource, marc)
  if marc['245']
    if marc['245']['a']
      title = marc['245']['a'].strip_trailing_punct
      resource.assert("[rda:titleProper]", marc['245']['a'].strip_trailing_punct)
    end
    if marc['245']['b']
      title << " "+marc['245']['b'].strip_trailing_punct
      resource.assert("[rda:otherTitleInformation]", marc['245']['b'].strip_trailing_punct)
    end
    if marc['245']['c']
      resource.assert("[rda:statementOfResponsibility]", marc['245']['c'].strip_trailing_punct)
    end
  end
  if marc['245']['n']
    resource.assert("[bibo:number]", marc['245']['n'])
  end
  resource.assert("[dcterms:title]", title)
  if marc['210']
    resource.assert("[bibo:shortTitle]", marc['210']['a'].strip_trailing_punct)
  end
  if marc['020'] && marc['020']['a']
    isbn = ISBN_Tools.cleanup(marc['020']['a'].strip_trailing_punct)
    if ISBN_Tools.is_valid?(isbn)
      if isbn.length == 10
        resource.assert("[bibo:isbn10]",isbn)
        resource.relate("[owl:sameAs]", "http://purl.org/NET/book/isbn/#{isbn}#book")
        resource.assert("[bibo:isbn13]", ISBN_Tools.isbn10_to_isbn13(isbn))
      else
        resource.assert("[bibo:isbn13]",isbn)
        resource.assert("[bibo:isbn10]", ISBN_Tools.isbn13_to_isbn10(isbn))          
        resource.relate("[owl:sameAs]", "http://purl.org/NET/book/isbn/#{ISBN_Tools.isbn13_to_isbn10(isbn)}#book")        
      end
    end    
  end
  
  if marc['022'] && marc['022']['a']
    resource.assert("[bibo:issn]", marc['022']['a'].strip_trailing_punct)
  end  
  
  subjects = marc.find_all {|field| field.tag =~ /^6../}
  
  subjects.each do | subject |
    literal = subject_to_string(subject)
    resource.assert("[dc:subject]", literal)
    if !["653","690","691","696","697", "698", "699"].index(subject.tag) && subject.indicator2 =~ /^(0|1)$/      
      
      authority = get_lcsh(literal)
      if authority
        resource.relate("[dcterms:subject]", authority)
      end
    end  
  end
  
  if marc['250'] && marc['250']['a']
    resource.assert("[bibo:edition]", marc['250']['a'])
  end
  if marc['246'] && marc['246']['a']
    resource.assert("[rda:parallelTitleProper]", marc['246']['a'].strip_trailing_punct)
  end
  if marc['767'] && marc['767']['t']
    resource.assert("[rda:parallelTitleProper]", marc['767']['t'].strip_trailing_punct)
  end  
end

def get_lcsh(subject_string)
  u = URI.parse("http://id.loc.gov/authorities/label/#{subject_string.gsub(/\s/,"%20")}")
  req = Net::HTTP::Get.new(u.path)
  res = Net::HTTP.start(u.host, u.port) {|http|
    http.request(req)
  }
  
  if res.code == "302"
    return res.header['location']
  end
  return nil
end

def to_rdfxml(resource)
  rdf = "<rdf:RDF"
  Curie.get_mappings.each_pair do |key, value|
    next unless resource.respond_to?(key.to_sym)
    rdf << " xmlns:#{key}=\"#{value}\""
  end
  unless rdf.match("http://www.w3.org/1999/02/22-rdf-syntax-ns#")
    rdf << " xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\""
  end
  rdf <<"><rdf:Description rdf:about=\"#{resource.uri}\">"
  Curie.get_mappings.each_pair do |key, value|
    if resource.respond_to?(key.to_sym)
      resource.send(key.to_sym).each_pair do | predicate, objects |
        [*objects].each do | object |
          rdf << "<#{key}:#{predicate}"
          if object.is_a?(RDFObject::ResourceReference)
            rdf << " rdf:resource=\"#{object.uri}\" />"
          else
            if object.language
              rdf << " xml:lang=\"#{object.language}\""
            end
            if object.data_type
              rdf << " rdf:datatype=\"#{object.data_type}\""
            end
            rdf << ">#{CGI.escapeHTML(object)}</#{key}:#{predicate}>"
          end
        end
      end
    end
  end
  rdf << "</rdf:Description></rdf:RDF>"
  rdf
end

def subject_to_string(subject)
  literal = ''
  subject.subfields.each do | subfield |
    if !literal.empty?
      if ["v","x","y","z"].index(subfield.code)
        literal << '--'
      else
        literal << ' ' if subfield.value =~ /^[\w\d]/
      end
    end
    literal << subfield.value
  end
  literal.strip_trailing_punct  
end


class String
  def slug
    slug = self.gsub(/[^A-z0-9\s\-]/,"")
    slug.gsub!(/\s/,"_")
    slug.downcase.strip_leading_and_trailing_punct
  end  
  def strip_trailing_punct
    self.sub(/[\.:,;\/\s]\s*$/,'').strip
  end
  def strip_leading_and_trailing_punct
    str = self.sub(/[\.:,;\/\s\)\]]\s*$/,'').strip
    return str.strip.sub(/^\s*[\.:,;\/\s\(\[]/,'')
  end  
  def lpad(count=1)
    "#{" " * count}#{self}"
  end
end

not_found do
  "Resource not found"
end
