
def select_object_display_labels(uri)
  sparql_query =<<END
  PREFIX skos: <http://www.w3.org/2004/02/skos/core#>
  PREFIX dcterms: <http://purl.org/dc/terms/>
  PREFIX rda: <http://RDVocab.info/Elements/>
  PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
  PREFIX foaf: <http://xmlns.com/foaf/0.1/>
  SELECT ?o ?skos_prefLabel ?dcterms_title ?rda_title ?rda_titleProper ?foaf_name ?rdfs_label
  WHERE
  {
    <#{uri}> ?p ?o .
    FILTER isURI(?o) .
    OPTIONAL { ?o skos:prefLabel ?skos_prefLabel } .
    OPTIONAL { ?o dcterms:title ?dcterms_title } .
    OPTIONAL { ?o rda:title ?rda_title } .
    OPTIONAL { ?o rda:titleProper ?rda_titleProper} .
    OPTIONAL { ?o foaf:name ?foaf_name } .
    OPTIONAL { ?o rdfs:label ?rdfs_label } .
  }
END
  response = STORE.sparql(sparql_query)
end

def parse_select_response(xml)
  results = []
  doc = Nokogiri::XML(xml)
  sparql_ns = {"sparql"=>"http://www.w3.org/2005/sparql-results#"}
  doc.xpath("/sparql:sparql/sparql:results/sparql:result", sparql_ns).each do | r |
    result = {}
    r.xpath("./sparql:binding", sparql_ns).each do |b|
      b.xpath("./sparql:uri", sparql_ns).each do | uri |
        result[b.attributes['name'].value] = RDFObject::Resource.new(uri.inner_text)
      end
      b.xpath("./sparql:literal", sparql_ns).each do | lit |
        result[b.attributes['name'].value] = RDF::Literal.new(lit.inner_text)
      end      
      
    end
    results << result
  end
  results
end

def sparql_var_to_curie(var)
  return 
end

def augment_object_display_labels(resource)
  sparql_response = select_object_display_labels(resource.uri)
  results = parse_select_response(sparql_response.body.content)
  r = {}
  results.each do | result |
    o = {}
    result.each_pair do |key, val|
      next if key == "o"
      o[key] = val
    end
    next if o.empty?    
    r[result["o"].uri] = o    
  end
  resource.assertions.each_pair do |pred, objects|
    [*objects].each do |object|
      next unless object && (object.is_a?(RDFObject::Node) || object.is_a?(RDFObject::ResourceReference)) && r[object.uri]
      r[object.uri].each_pair do |k,val|
        object.assert("[#{k.sub(/_/,":")}]", val)
      end
    end
  end
end