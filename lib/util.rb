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
require File.dirname(__FILE__) + '/linked_lccn'

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
  puts dbconf.inspect
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
    response = STORE.augment(collection[uri].to_rss)
    augmented_collection = RDFObject::Parser.parse(response.body.content)
    resource = augmented_collection[uri]
    resource.rss.delete("title") if resource.rss && resource.rss["title"] = "Item"
    resource.rss.delete("link") if resource.rss && resource.rss["link"] = uri
    if resource.rdf && resource.rdf['type']
      [*resource.rdf['type']].each do | rdf_type |
        next unless rdf_type
        if rdf_type.uri == "http://purl.org/rss/1.0/item"
          resource.rdf['type'].delete(rdf_type) 
        end
      end
    end
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
    status(206)
    lccn.cache_rdf
    Delayed::Job.enqueue  AdvancedEnrichGraphJob.new(lccn)
  end
  resource
end

def fetch_from_platform(uri)
  response = STORE.describe(uri)
  collection = Parser.parse(response.body.content, "rdfxml")
  return collection unless collection.empty?
  false
end

class AdvancedEnrichGraphJob < Struct.new(:lccn)
  def perform
    DJ_LOGGER << "Enriching #{lccn.graph.uri}\n"
    lccn.background_tasks
    DJ_LOGGER << "Enriched #{lccn.graph.uri}\n"
    res = STORE.store_data(lccn.graph.to_xml(3))
    DJ_LOGGER << "Saved #{lccn.graph.uri}\n"
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

