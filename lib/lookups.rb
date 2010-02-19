def get_lcsh(subject_string)
  u = URI.parse("http://id.loc.gov/authorities/label/#{subject_string.gsub(/\s/,"%20")}")
  req = Net::HTTP::Get.new(u.path)
  res = Net::HTTP.start(u.host, u.port) {|http|
    http.request(req)
  }
  
  if res.code == "302"
    uri = res.header['location']
    concept = Resource.new(uri)
    concept.describe
    return concept
  end
  return nil
end

def dbtune_lookup(upc)
  uri = URI.parse("http://dbtune.org/musicbrainz/sparql")
  sparql = <<SPARQL
PREFIX mo: <http://purl.org/ontology/mo/>
DESCRIBE * WHERE {
  ?obj mo:barcode "#{upc}"
}
SPARQL
  uri.query = "query=#{CGI.escape(sparql)}"
  response = Net::HTTP.get uri
  resources = {:record=>nil, :release=>nil}
  collection = Parser.parse response
  return nil if collection.empty?
  releases = collection.find_by_predicate("[rdf:type]")
  releases.each do | r |
    break unless r.is_a?(Array)
    r.each do | release |
      next unless release.is_a?(Resource)
      resources[:release] = release if release['[mo:barcode]'] == upc
    end
  end
  records = collection.find_by_predicate("[mo:release]")
  records.each do | r |
    break unless r.is_a?(Array)
    r.each do | record |
      next unless record.is_a?(Resource)
      record.describe
      resources[:record] = record
    end
  end  
  resources
end

def musicbrainz_lookup(params)
  return unless params[:title] && params[:artist]
  query = MusicBrainz::Webservice::Query.new
  includes = MusicBrainz::Webservice::ReleaseIncludes.new(:release_events=>true, :tracks=>true, :track_rels=>true, :release_rels=>true, :labels=>true)
  results = query.get_releases(MusicBrainz::Webservice::ReleaseFilter.new(:title=>params[:title],:artist=>params[:artist]))
  matches = {}
  results.each do | result |
#    next unless result.entity.title.downcase == params[:title].downcase
    result.entity.release_events.each do | event |
      if event.label && params[:label]
        if check_mbrainz_label(params[:label], event.label)
          if (params[:barcode] && params[:barcode].index(event.barcode)) or (params[:catno] && params[:catno].index(event.catalog_number))
            
            record = Resource.new("http://dbtune.org/musicbrainz/resource/record/#{result.entity.id.uuid}")
            matches[:record] ||= []
            unless resource_in_array?(record, matches[:record])
              begin
                record.describe            
              rescue Timeout::Error
              end
              matches[:record] << record
            end
            if record.empty_graph?
              mbz_release = query.get_release_by_id(result.entity.id.uuid, includes)
              mbz_release.release_events.each do | mbz_event |
                if check_mbrainz_label(params[:label], mbz_event.label)
                  if (params[:barcode] && params[:barcode].index(mbz_event.barcode)) or (params[:catno] && params[:catno].index(mbz_event.catalog_number))                
                    matches[:labels] ||= []
                    label = Resource.new("http://dbtune.org/musicbrainz/resource/label/#{mbz_event.label.id.uuid}")
                    matches[:labels] << label unless resource_in_array?(label, matches[:labels])
                  end
                end
              end 
              mbz_release.tracks.each do | track |             
                matches[:tracks] ||= []
                t = Resource.new("http://dbtune.org/musicbrainz/resource/track/#{track.id.uuid}")
                matches[:tracks] << t unless resource_in_array?(t, matches[:tracks])
              end
            else
              record.mo['release'].each do | mbz_event |
                mbz_event.describe
                if (params[:barcode] && params[:barcode].index(mbz_event.mo['barcode'])) or 
                  (params[:catno] && params[:catno].index(mbz_event["http://dbtune.org/musicbrainz/resource/vocab/release_catno"]))
                  match = false
                  if mbz_event.mo['release_label']
                    mbz_event.mo['release_label'].describe
                    [*mbz_event.mo['release_label']['http://dbtune.org/musicbrainz/resource/vocab/alias']].each do |label_alias|
                      params[:label].each do | lccn_label |
                        if lccn_label.downcase =~ /#{label_alias.downcase}/ or label_alias.downcase =~ /#{lccn_label.downcase}/
                          match = true
                        end
                      end
                    end
                  end
                  if match
                    matches[:release] ||= []                    
                    unless resource_in_array?(mbz_event, matches[:release])                   
                      matches[:release] << mbz_event
                    end
                    matches[:labels] ||= []
                    unless resource_in_array?(mbz_event.mo['release_label'], matches[:labels])
                      matches[:labels] << mbz_event.mo['release_label']
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end
  matches
end

def check_mbrainz_label(lccn_label, mbrainz_label)
  lccn_label.each do | l_label |
    return true if l_label.downcase =~ /#{mbrainz_label.name.downcase}/ or mbrainz_label.name.downcase =~ /#{l_label.downcase}/
    mbrainz_label.aliases.each do | label_alias |
      return true if l_label.downcase =~ /#{label_alias.name.downcase}/ or label_alias.name.downcase =~ /#{l_label.downcase}/
    end
  end
  false
end

def resource_in_array?(resource, array)
  array.each do | r |
    if r.uri == resource.uri
      return true
    end
  end
  false
end

def dbtune_catalog_number_lookup(label, number)
  uri = URI.parse("http://dbtune.org/musicbrainz/sparql")
  sparql = <<SPARQL
PREFIX mo: <http://purl.org/ontology/mo/>
PREFIX vocab: <http://dbtune.org/musicbrainz/resource/vocab/>
DESCRIBE ?s WHERE {
?label vocab:alias ?labelname .
?s vocab:release_catno "#{number}" .
?s mo:release_label ?label .
FILTER regex(?labelname, "#{label}", "i")
}
SPARQL
  uri.query = "query=#{CGI.escape(sparql)}"
  puts uri.to_s
  begin
    response = Net::HTTP.get uri
  rescue Timeout::Error
    return
  end
  resources = {:record=>nil, :release=>nil}
  collection = Parser.parse response
  return nil if collection.empty?
  release = collection.find_by_predicate_and_object("http://dbtune.org/musicbrainz/resource/vocab/release_catno", number)
  resources[:release] = release.values if release
  records = collection.find_by_predicate("[mo:release]")
  records.values.each do | record |
    record.describe
  end
  resources[:record] = records.values
  resources
end

def openlibrary_lookup(lccn)
  uri = URI.parse "http://openlibrary.org/query.json?type=/type/edition&lccn=#{CGI.escape(lccn)}&*="
  response = JSON.parse(Net::HTTP.get(uri))
  return nil if response.empty?
  return response
end

def linkedmdb_lookup(title)

sparql = <<SPARQL
PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
PREFIX foaf: <http://xmlns.com/foaf/0.1/>
PREFIX movie: <http://data.linkedmdb.org/resource/movie/>
PREFIX dc: <http://purl.org/dc/terms/>
DESCRIBE * WHERE {
 ?obj rdf:type movie:film .
 ?obj dc:title ?title FILTER regex(?title, "^#{title}$", "i" )
}
SPARQL
  uri = "http://data.linkedmdb.org/sparql?query=#{CGI.escape(sparql)}"
  begin
    response = RDFObject::HTTPClient.fetch(uri)
    collection = XMLParser.parse response[:content]
  rescue 
    return nil
  end
  return nil if collection.empty?
  resources = collection.find_by_predicate("[rdf:type]")
  resources.each do | r |
    break unless r.is_a?(Array)
    r.each do | resource |
      next unless resource.is_a?(Resource)
      [*resource['[rdf:type]']].each do | type |
        return resource if type.uri == "http://data.linkedmdb.org/resource/movie/film"
      end
    end
  end
  nil
end

def freebase_film_lookup(title, year=nil)
  
  resources = Ken.all(:name=>title, :"author~="=>fuzz_auth, :type=>"/film/film")
  matched_resource = nil
  resources.each do | resource |
    if resources.length == 1
      matched_resource = resource
      break
    end
  end
  if matched_resource
    r = Resource.new("http://rdf.freebase.com/ns/#{matched_resource.id.sub(/^\//,"").gsub(/\//,".")}")
    return r
  else
    return nil
  end
end

def dbpedia_film_lookup(title)
 
sparql = <<SPARQL
PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
PREFIX foaf: <http://xmlns.com/foaf/0.1/>
DESCRIBE * WHERE {
?obj rdf:type <http://dbpedia.org/ontology/Film> .
?obj foaf:name ?title FILTER regex(?title, "^#{title}$", "i" )
}
SPARQL
  uri = "http://dbpedia.org/sparql?query=#{CGI.escape(sparql)}"
  response = RDFObject::HTTPClient.fetch(uri)
  collection = XMLParser.parse response[:content]
  return nil if collection.empty?
  resources = collection.find_by_predicate("[rdf:type]")
  resources.each do | r |
    break unless r.is_a?(Array)
    r.each do | resource |
      next unless resource.is_a?(Resource)
      [*resource['[rdf:type]']].each do | type |
        return resource if type.uri == "http://dbpedia.org/ontology/Film"
      end
    end
  end
  nil
end

def viaf_by_id(id)
  id.sub!(/#i$/,"")
  resource = Resource.new("http://purl.org/NET/lccn/people/#{id}#i")
  id_with_space = id.sub(/^n/, "n ")
  query = "cql.serverChoice all \"LC|"+id_with_space+"\""
  results = viaf_search(query)
  results.each do | result |
    result.find('//v:VIAFCluster/v:sources/v:source', 'v:http://viaf.org/Domain/Cluster/terms#').each do | source |
      (src, ident) = source.inner_xml.split("|")
      next unless src == "LC"
      lccn = ident.gsub(/\s/,"")
      puts lccn
      if lccn == id      
        result.find('//v:VIAFCluster/v:mainHeadings/v:data/v:text', 'v:http://viaf.org/Domain/Cluster/terms#').each do | main_heading |
          resource.assert("[foaf:name]", main_heading.inner_xml)
          result.find('//v:VIAFCluster/v:viafID', 'v:http://viaf.org/Domain/Cluster/terms#').each do | viaf_id |
            uri = "http://viaf.org/viaf/#{viaf_id.inner_xml}.rwo"
            concept = Resource.new(uri)
            concept.describe
            resource.relate("[rdf:type]", "[foaf:Person]")

            resource.relate("[umbel:isAbout]", concept)
            # Clean up viaf's wonky dbpedia associations.
            [*concept.foaf['page']].each do | page |
              u = URI.parse page.uri
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
  resource
end

def viaf_search(query)
  client = SRU::Client.new("http://viaf.org/search", :parser=>"libxml")
  opts = {:maximumRecords=>5, :startRecord=>1, :recordSchema=>"VIAF"}
  client.search_retrieve query, opts
end

def viaf_lookup(name, subject=false)

  name_values = []
  name.each do | subfield |
    next if (subfield.code == 't') or (subfield.code == '4')
    name_values << subfield.value
  end
  results = viaf_search("local.names all \"#{name_values.join(" ").strip_trailing_punct}\"")
  results.each do | result |
    result.find('//v:VIAFCluster/v:mainHeadings/v:data/v:text', 'v:http://viaf.org/Domain/Cluster/terms#').each do | main_heading |
      if main_heading.inner_xml == name_values.join(" ").strip_trailing_punct
        result.find('//v:VIAFCluster/v:viafID', 'v:http://viaf.org/Domain/Cluster/terms#').each do | viaf_id |
          uri = "http://viaf.org/viaf/#{viaf_id.inner_xml}.rwo"
          concept = Resource.new(uri)
          concept.describe
          return concept if subject
          lccn = nil
          result.find('//v:VIAFCluster/v:sources/v:source', 'v:http://viaf.org/Domain/Cluster/terms#').each do | source |
            (src, id) = source.inner_xml.split("|")
            next unless src == "LC"
            lccn = id.gsub(/\s/,"")
          end
          uri = "http://purl.org/NET/lccn/people/#{lccn}#i"
          resource = Resource.new(uri)          
          resource.relate("[rdf:type]", "[foaf:Person]")
          resource.assert("[foaf:name]", name_values.join(" ").strip_trailing_punct)    
          resource.relate("[umbel:isAbout]", concept)
          # Clean up viaf's wonky dbpedia associations.
          if concept.foaf
            [*concept.foaf['page']].each do | page |
              u = URI.parse page.uri
              next unless u.host == "dbpedia.org"
              u.path.sub!(/^\/page\//,"/resource/")
              u.path.sub!(/Wikipedia\:WikiProject_/,"")
              resource.relate("[owl:sameAs]", u.to_s)
            end
          end
          return resource
        end
      end
    end
  end
  nil
end


def freebase_book_lookup(title, author)
  fuzz_auth = author['a'].split(",")[0]
  resources = Ken.all(:name=>title, :"author~="=>fuzz_auth, :type=>"/book/written_work")
  matched_resource = nil
  resources.each do | resource |
    if resources.length == 1
      matched_resource = resource
      break
    end
  end
  if matched_resource
    r = Resource.new("http://rdf.freebase.com/ns/#{matched_resource.id.sub(/^\//,"").gsub(/\//,".")}")
    return r
  else
    return nil
  end
end

def freebase_journal_lookup(title, issn=nil)
  resources = Ken.all(:name=>title, :ISSN=>issn, :type=>"/book/periodical")
  matched_resource = nil
  resources.each do | resource |
    if resources.length == 1
      matched_resource = resource
      break
    end
  end
  if matched_resource
    r = Resource.new("http://rdf.freebase.com/ns/#{matched_resource.id.sub(/^\//,"").gsub(/\//,".")}")
    return r
  else
    return nil
  end
end

def dbpedia_journal_lookup(title, issn)
 
sparql = <<SPARQL
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
PREFIX dbpedia: <http://dbpedia.org/property/>
DESCRIBE * WHERE {
?obj dbpedia:issn ?issn FILTER regex(?issn, "#{issn}", "i") .
?obj rdfs:label ?title FILTER regex(?title, "^#{title}$", "i" )
}
SPARQL
  uri = "http://dbpedia.org/sparql?query=#{CGI.escape(sparql)}"
  response = RDFObject::HTTPClient.fetch(uri)
  collection = XMLParser.parse response[:content]
  return nil if collection.empty?
  resources = collection.find_by_predicate("http://dbpedia.org/property/issn")
  resources.each do | r |
    break unless r.is_a?(Array)
    r.each do | resource |
      next unless resource.is_a?(Resource)
      return resource
    end
  end
  nil
end

def loc_creator_search(creator)
  client = SRU::Client.new("http://z3950.loc.gov:7090/Voyager")
  client.version = "1.1"
  queries = []
  [*creator.foaf['name']].each do | name |
    queries << "(dc.creator all \"#{name}\")"
  end
  opts = {:startRecord=>1, :maximumRecords=>50, :recordSchema=>'marcxml'}
  queries.each do | slice |
    i = 0
    total = 50
    while i < total
      results = client.search_retrieve(slice, opts)
      results.doc.each_element('//datafield[@tag="010"]/subfield[@code="a"]') do | lccn_tag |
        lccn = lccn_tag.get_text.value.strip.gsub(/\s/,"")
        creator.relate("[foaf:made]", "http://purl.org/NET/lccn/#{CGI.escape(lccn)}#i")      
      end
      total = results.number_of_records
      i += 50
    end
  end
end

def get_marc(lccn)
  uri = URI.parse "http://lccn.loc.gov/#{lccn.gsub(/\s/,"%20")}/marcxml"
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
