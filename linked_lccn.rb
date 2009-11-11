require 'rubygems'
require 'sinatra'
require 'json'
require 'net/http'
require 'enhanced_marc'
require 'rdf_objects'
require 'isbn/tools'
require 'sru'
load 'lib/lookups.rb'
load 'lib/marc_methods.rb'
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

get '/subjects/:label' do
  concept = Resource.new("http://purl.org/NET/lccn/subjects/#{CGI.escape(params[:label])}")
  concept.relate("[rdf:type]", "[skos:Concept]")
  concept.assert("[skos:prefLabel]", params[:label])
  content_type 'application/rdf+xml', :charset => 'utf-8'  
  to_rdfxml(concept)
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
  rdf <<">"
  rdf << rdf_description_block(resource, 0)
  rdf << "</rdf:RDF>"
  rdf
end

def rdf_description_block(resource, depth)
  rdf = "<rdf:Description rdf:about=\"#{CGI.escapeHTML(resource.uri)}\">"
  Curie.get_mappings.each_pair do |key, value|
    if resource.respond_to?(key.to_sym)
      resource.send(key.to_sym).each_pair do | predicate, objects |
        [*objects].each do | object |
          rdf << "<#{key}:#{predicate}"
          rdf << " xmlns:#{key}=\"#{Curie.parse("[#{key}:]")}\""
          if object.is_a?(RDFObject::ResourceReference)
            if depth > 0
              rdf << " rdf:resource=\"#{CGI.escapeHTML(object.uri)}\" />"
            else
              rdf << ">"
              rdf << rdf_description_block(object.resource, depth+1)
              rdf << "</#{key}:#{predicate}>"
            end
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
  rdf << "</rdf:Description>"
  rdf
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
