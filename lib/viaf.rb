class LinkedLCCN::VIAF
  def self.lookup_by_lccn(id)
    id.sub!(/#i$/,"")
    resource = RDFObject::Resource.new("http://purl.org/NET/lccn/people/#{id}#i")
    id_with_space = id.sub(/^n/, "n ")
    query = "cql.serverChoice all \"LC|"+id_with_space+"\""
    results = self.search(query)
    results.each do | result |      
      result.find('//v:VIAFCluster/v:sources/v:source', 'v:http://viaf.org/viaf/terms#').each do | source |
        (src, ident) = source.inner_xml.split("|")
        next unless src == "LC"
        lccn = ident.gsub(/\s/,"")
        if lccn == id      
          result.find('//v:VIAFCluster/v:mainHeadings/v:data/v:text', 'v:http://viaf.org/viaf/terms#').each do | main_heading |
            resource.assert("[foaf:name]", main_heading.inner_xml)
            result.find('//v:VIAFCluster/v:viafID', 'v:http://viaf.org/viaf/terms#').each do | viaf_id |
              concept_uri = "http://viaf.org/viaf/#{viaf_id.inner_xml}/#skos:Concept"
              foaf_uri = "http://viaf.org/viaf/#{viaf_id.inner_xml}/#foaf:Person"
              viaf_collection = RDFObject::Parser.parse("http://viaf.org/viaf/#{viaf_id.inner_xml}/rdf.xml")
              concept = viaf_collection[concept_uri]
              foaf = viaf_collection[foaf_uri]
              normalize_uris(concept)
              resource.relate("[rdf:type]", "[foaf:Person]")
              resource.relate("[owl:sameAs]", foaf)
              resource.relate("[umbel:isAbout]", concept)
              # Clean up viaf's wonky dbpedia associations.
              if foaf.dcterms && foaf.dcterms['relation']
                [*foaf.dcterms['relation']].each do | dbpedia |
                  u = Addressable::URI.parse dbpedia.uri
                  u.normalize!
                  next unless u.host == "dbpedia.org"
                  u.path.sub!(/^\/page\//,"/resource/")
                  u.path.sub!(/Wikipedia\:WikiProject_/,"")
                  resource.relate("[owl:sameAs]", u.to_s) 
                end
              end
            end
          end
        end
      end
    end
    resource
  end

  def self.search(query)
    client = SRU::Client.new("http://viaf.org/viaf/search", :parser=>"libxml")
    opts = {:maximumRecords=>5, :startRecord=>1, :recordSchema=>"VIAF"}
    client.search_retrieve query, opts
  end

  def self.lookup_by_name(name, subject=false)
    name_values = []
    name.each do | subfield |
      next if (subfield.code == 't') or (subfield.code == '4')
      name_values << subfield.value
    end
    results = self.search("local.names all \"#{name_values.join(" ").strip_trailing_punct}\"")
    resource = nil
    results.each do | result |
      
      result.find('.//v:VIAFCluster/v:mainHeadings/v:data/v:text', 'v:http://viaf.org/viaf/terms#').each do | main_heading |
        if main_heading.inner_xml == name_values.join(" ").strip_trailing_punct
          result.find('.//v:VIAFCluster/v:viafID', 'v:http://viaf.org/viaf/terms#').each do | viaf_id |
            concept_uri = "http://viaf.org/viaf/#{viaf_id.inner_xml}/#skos:Concept"
            foaf_uri = "http://viaf.org/viaf/#{viaf_id.inner_xml}/#foaf:Person"
            viaf_collection = RDFObject::Parser.parse("http://viaf.org/viaf/#{viaf_id.inner_xml}/rdf.xml")
            concept = viaf_collection[concept_uri]
            foaf = viaf_collection[foaf_uri]
            normalize_uris(concept)            
            return concept if subject
            lccn = nil
            result.find('.//v:VIAFCluster/v:sources/v:source', 'v:http://viaf.org/viaf/terms#').each do | source |
              (src, id) = source.inner_xml.split("|")
              next unless src == "LC"
              lccn = id.gsub(/\s/,"")
            end
            uri = "http://purl.org/NET/lccn/people/#{lccn}#i"
            resource = RDFObject::Resource.new(uri)          
            resource.relate("[rdf:type]", "[foaf:Person]")
            resource.assert("[foaf:name]", name_values.join(" ").strip_trailing_punct)    
            resource.relate("[umbel:isAbout]", concept)
            # Clean up viaf's wonky dbpedia associations.
            if foaf.dcterms && foaf.dcterms['relation']
              [*foaf.dcterms['relation']].each do | dbpedia |
                u = Addressable::URI.parse dbpedia.uri
                u.normalize!
                next unless u.host == "dbpedia.org"
                u.path.sub!(/^\/page\//,"/resource/")
                u.path.sub!(/Wikipedia\:WikiProject_/,"")
                resource.relate("[owl:sameAs]", u.to_s) 
              end
            end
            return resource if lccn
          end
        end
      end
    end
    if resource
      return resource.umbel['isAbout']
    end
    nil
  end
  
  def self.normalize_uris(resource)
    resource.assertions.each do |predicate,objects|
      [*objects].each do |object|
        if object.is_a?(RDFObject::Resource) or object.is_a?(RDFObject::ResourceReference) 
          object.uri = Addressable::URI.normalized_encode(object.uri)
        end
      end
    end
  end
  
end