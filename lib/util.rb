require 'json'
require 'net/http'
require 'enhanced_marc'
require 'rdf_objects'
require 'isbn/tools'
require 'rbrainz'
require 'sru'
require 'yaml'
require 'pho'

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

def fetch_resource(uri)
  resource = RDFObject::Resource.new(uri)
  if collection = fetch_from_platform(uri)
    response = STORE.augment(collection[uri].to_rss)
    augmented_collection = RDFObject::Parser.parse(response.body.content)
    resource = augmented_collection[uri]
    resource.rss.delete("title") if resource.rss && resource.rss["title"] = "Item"
    resource.rss.delete("link") if resource.rss && resource.rss["link"] = uri
  elsif uri =~ /\/people\//
    resource = viaf_by_id(params[:id])
    loc_creator_search(resource)
    STORE.store_data(resource.to_xml(2))    
  else
    marc = get_marc(params["id"])
    not_found if marc.nil?
    resource = to_rdf(marc)
    STORE.store_data(resource.to_xml(2))
  end
  resource
end

def fetch_from_platform(uri)
  response = STORE.describe(uri)
  collection = Parser.parse(response.body.content, "rdfxml")
  return collection unless collection.empty?
  false
end

class RDFObject::Resource
  def describe
    response = STORE.describe(self.uri)
    local_collection = Parser.parse(response.body.content, :format=>"rdfxml")
    unless local_collection && local_collection[self.uri]
      response = RDFObject::HTTPClient.fetch(self.uri)
      local_collection = RDFObject::Parser.parse(response[:content], {:base_uri=>response[:uri]})
      return unless local_collection && local_collection[self.uri]
    end
    local_collection[self.uri].assertions.each do | predicate, object |
      [*object].each do | obj |
        self.assert(predicate, obj) unless self.assertion_exists?(predicate, obj)
      end
    end
  end  
  
  def to_rss
    namespaces, rdf_data = self.rss_item_block
    unless namespaces["xmlns:rdf"]
      if  x = namespaces.index("http://www.w3.org/1999/02/22-rdf-syntax-ns#")
        namespaces.delete(x)
      end
      namespaces["xmlns:rdf"] = "http://www.w3.org/1999/02/22-rdf-syntax-ns#"
    end
    namespaces["xmlns"] = "http://purl.org/rss/1.0/"
    uri = self.uri.sub(/#.*$/,".rss")
    rdf = "<rdf:RDF"
    namespaces.each_pair {|key, value| rdf << " #{key}=\"#{value}\""}
    rdf <<">"
    rdf << "<channel rdf:about=\"#{uri}\"><title>#{self.uri}</title><link>#{self.uri}</link>"
    rdf << "<description>#{self.uri}</description><items><rdf:Seq><rdf:li resource=\"#{self.uri}\" /></rdf:Seq></items>"
    rdf << "</channel>"
    rdf << rdf_data
    rdf << "</rdf:RDF>"
    rdf      
  end   
  
  def rss_item_block
    rdf = "<item #{xml_subject_attribute}>"
    rdf << "<title>Item</title>"
    rdf << "<link>#{self.uri}</link>"
    namespaces = {}
    Curie.get_mappings.each_pair do |key, value|
      if self.respond_to?(key.to_sym)
        self.send(key.to_sym).each_pair do | predicate, objects |
          [*objects].each do | object |
            rdf << "<#{key}:#{predicate}"
            namespaces["xmlns:#{key}"] = "#{Curie.parse("[#{key}:]")}"
            if object.is_a?(RDFObject::ResourceReference)
              rdf << " #{object.xml_object_attribute} />"              
            else
              if object.language
                rdf << " xml:lang=\"#{object.language}\""
              end
              if object.data_type
                rdf << " rdf:datatype=\"#{object.data_type}\""
              end
              rdf << ">#{CGI.escapeHTML(object.to_s)}</#{key}:#{predicate}>"
            end
          end
        end
      end
    end
    rdf << "</item>"
    [namespaces, rdf]
  end   
end