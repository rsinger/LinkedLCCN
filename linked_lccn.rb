require 'rubygems'
require 'sinatra'

require 'net/http'
require 'enhanced_marc'
require 'rdf_objects'
include RDFObject

configure do
  Curie.add_prefixes! :mo=>"http://purl.org/ontology/mo/", :skos=>"http://www.w3.org/2004/02/skos/core#",
   :owl=>'http://www.w3.org/2002/07/owl#', :wgs84 => 'http://www.w3.org/2003/01/geo/wgs84_pos#', 
   :dcterms => 'http://purl.org/dc/terms/', :bibo => 'http://purl.org/ontology/bibo/'
end
get '/:id' do
  marc = get_marc(params["id"])
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
  rdf = case marc.class.to_s
  when "MARC::SoundRecord" then model_sound(marc)
  end
  rdf
end

def model_sound(marc)
  id = marc['010'].value.strip
  resource = Resource.new("http://lccn.code4lib.org/#{id}")
  resource.relate("[rdf:type]", "[mo:Recording]")
  resource.relate("[owl:sameAs]", "http://lccn.loc.gov/#{id}")
  resource.assert("[dcterms:title]", Literal.new(marc['245']['a']))
  resource
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
