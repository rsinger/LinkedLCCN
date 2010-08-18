$:.unshift *Dir[File.dirname(__FILE__) + "/../vendor/*/lib"]
require 'logger'
require 'active_record'
require 'delayed_job'
require 'json'
require 'net/http'
require 'enhanced_marc'
require 'rdf_objects'
require 'isbn/tools'
require 'sru'
require 'yaml'
require 'pho'
require 'addressable/uri'
require File.dirname(__FILE__) + '/linked_lccn'
require File.dirname(__FILE__) + '/sparql_queries'

include RDFObject
unless ENV['PLATFORM_STORE']
  CONFIG = YAML.load_file(File.dirname(__FILE__) + '/../config/config.yml')
end
RELATORS = {:missing=>[]}
RELATORS[:codes] = YAML.load_file(File.dirname(__FILE__) + '/relators.yml')
STORE = Pho::Store.new(ENV['PLATFORM_STORE'] || CONFIG['store']['uri'], 
  ENV['PLATFORM_USERNAME'] || CONFIG['store']['username'],
  ENV['PLATFORM_PASSWORD'] || CONFIG['store']['password'])
DJ_LOGGER = Logger.new(File.dirname(__FILE__) + '/../log/dj.log')  
def init_environment
  init_database
  init_curies
end

def init_curies
  Curie.add_prefixes! :mo=>"http://purl.org/ontology/mo/", :skos=>"http://www.w3.org/2004/02/skos/core#",
   :owl=>'http://www.w3.org/2002/07/owl#', :wgs84 => 'http://www.w3.org/2003/01/geo/wgs84_pos#', 
   :dcterms => 'http://purl.org/dc/terms/', :bibo => 'http://purl.org/ontology/bibo/', :rda=>"http://RDVocab.info/Elements/",
   :role => 'http://RDVocab.info/roles/', :umbel => 'http://umbel.org/umbel#', :meta=>"http://purl.org/NET/lccn/vocab/",
   :rss => "http://purl.org/rss/1.0/"
end  

def init_database
  dbconf = CONFIG['database']
  ActiveRecord::Base.establish_connection(dbconf) 
  ActiveRecord::Base.logger = Logger.new(File.open(File.dirname(__FILE__) + '/../log/database.log', 'a')) 
  ActiveRecord::Migrator.up(File.dirname(__FILE__) + '/../db/migrate')
end  

MARC::XMLReader.nokogiri!

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
    resource = collection[uri]
    augment_object_display_labels(resource)
  elsif uri =~ /\/people\//
    resource = LinkedLCCN::VIAF.lookup_by_lccn(params[:id])
    unless resource.empty_graph?
      LinkedLCCN::LibraryOfCongress.creator_search(resource)
      STORE.store_data(resource.to_xml(2))    
    end
  elsif uri =~ /\/subjects\//
    resource.relate("[rdf:type]", "[skos:Concept]")
    resource.assert("[skos:prefLabel]", params[:label])
  else
    lccn = LinkedLCCN::LCCN.new(params["id"])
    lccn.get_marc
    not_found if lccn.marc.nil?
    lccn.basic_rdf
    resource = lccn.graph
    status(202)
    headers['Retry-After'] = "120"
    store_object_in_platform(lccn)
    Delayed::Job.enqueue  AdvancedEnrichGraphJob.new(lccn.lccn)
  end
  resource
end

def parse_sparql_count(response)
  xml = Nokogiri::XML(response)
  if c = xml.xpath("/sparql:sparql/sparql:results/sparql:result/sparql:binding/sparql:literal[@datatype='http://www.w3.org/2001/XMLSchema#integer']",
     'sparql'=> "http://www.w3.org/2005/sparql-results#")
     count = c.inner_text
     return count.to_i
  end
  0
end

def generate_sparql_count(condition, prefixes={})
  string = "PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>\n"
  prefixes.each_pair do |key, uri|
    string << "PREFIX #{key}: <#{uri}>\n"
  end
  string << "SELECT (count(?s) as ?count) WHERE {\n?s "
  string << condition
  string << " }"
  string
end
def get_uri_for_zeitgeist(condition, offset, prefixes={})
  string = "PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>\n"
  prefixes.each_pair do |key, uri|
    string << "PREFIX #{key}: <#{uri}>\n"
  end
  string << "SELECT ?s WHERE {\n?s "
  string << condition
  string << " }\n"
  string << "OFFSET #{offset} LIMIT 1"
  string
  response = STORE.sparql(string)
  xml = Nokogiri::XML(response.body.content)
  uri = xml.xpath("/sparql:sparql/sparql:results/sparql:result/sparql:binding/sparql:uri", 'sparql'=> "http://www.w3.org/2005/sparql-results#")
  if uri
    return uri.inner_text
  end
end
def fetch_zeitgeist
  zeitgeist = {}
  response = STORE.sparql(generate_sparql_count("?p ?o"))
  zeitgeist[:triple_count] = parse_sparql_count(response.body.content)
  response = STORE.sparql(generate_sparql_count("rdf:type bibo:Book", {'bibo'=>"http://purl.org/ontology/bibo/"}))
  zeitgeist[:book_count] = parse_sparql_count(response.body.content)
  zeitgeist[:book] = STORE.describe(get_uri_for_zeitgeist("rdf:type bibo:Book", rand(zeitgeist[:book_count]), {'bibo'=>"http://purl.org/ontology/bibo/"}))
  response = STORE.sparql(generate_sparql_count("rdf:type mo:MusicRelease", {"mo"=>"http://purl.org/ontology/mo/"}))
  zeitgeist[:music_count] = parse_sparql_count(response.body.content)
  zeitgeist[:music] = STORE.describe(get_uri_for_zeitgeist("rdf:type mo:MusicRelease", rand(zeitgeist[:music_count]), {"mo"=>"http://purl.org/ontology/mo/"}))  
  response = STORE.sparql(generate_sparql_count("rdf:type foaf:Person", {"foaf"=>Curie.parse("[foaf:]")}))
  zeitgeist[:person_count] = parse_sparql_count(response.body.content)
  zeitgeist[:person] = STORE.describe(get_uri_for_zeitgeist("rdf:type foaf:Person", rand(zeitgeist[:person_count]), {"foaf"=>Curie.parse("[foaf:]")}))  
  zeitgeist
end

def fetch_from_platform(uri)
  response = STORE.describe(uri)
  collection = Parser.parse(response.body.content, "rdfxml")
  return collection unless collection.empty?
  false
end

def augment_resource(resource)
  collection = RDFObject::Collection.new
  collection[resource.uri] = resource
  collection = augment_collection(resource.uri, collection)
  puts collection.inspect
  collection[resource.uri].assertions.each_pair do | predicate, objects |

    [*objects].each do |object|
      next unless object && (object.is_a?(RDFObject::Node) || object.is_a?(RDFObject::ResourceReference))
      if collection[object.uri]   
        collection[object.uri].assertions.each_pair do |p, o|
          [*o].each do |obj|
            next unless obj
            object.assert(p, obj)
          end
        end
      end
    end

  end
  return collection[resource.uri]
end

def augment_collection(uri, collection)
  describe_objects =<<END
DESCRIBE ?o
WHERE
{
  <#{uri}> ?p ?o 
}
END
  sparql_response = STORE.sparql_describe(describe_objects, "text/plain")
  parser = RDFObject::NTriplesParser.new
  parser.collection = collection
  parser.data = sparql_response.body.content
  return parser.parse
end

def store_object_in_platform(lccn)
  
  STORE.upload_item(StringIO.new(lccn.to_json), "application/json", lccn.lccn)
end

class AdvancedEnrichGraphJob < Struct.new(:lccn)
  def perform
    r = STORE.get_item("/items/#{lccn}")
    return unless r.status == 200
    l = LinkedLCCN::LCCN.new_from_json(JSON.parse(r.body.content))
    DJ_LOGGER << "Enriching #{l.graph.uri}\n"
    l.background_tasks
    DJ_LOGGER << "Enriched #{l.graph.uri}\n"
    res = STORE.store_data(l.graph.to_xml(3))
    DJ_LOGGER << "Saved #{l.graph.uri}\n"
    STORE.delete_item("/items/#{lccn}")
  end
end

class CreatorEnhance < Struct.new(:resource)
  
end

class RDFObject::Resource
  def describe
    response = STORE.describe(self.uri)
    local_collection = RDFObject::Parser.parse(response.body.content, :format=>"rdfxml")
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

