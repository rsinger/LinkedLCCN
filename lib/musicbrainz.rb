require 'rbrainz'
class LinkedLCCN::MusicBrainz
  def self.lookup(params)
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

              record = RDFObject::Resource.new("http://dbtune.org/musicbrainz/resource/record/#{result.entity.id.uuid}")
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
                      label = RDFObject::Resource.new("http://dbtune.org/musicbrainz/resource/label/#{mbz_event.label.id.uuid}")
                      matches[:labels] << label unless resource_in_array?(label, matches[:labels])
                    end
                  end
                end 
                mbz_release.tracks.each do | track |             
                  matches[:tracks] ||= []
                  t = RDFObject::Resource.new("http://dbtune.org/musicbrainz/resource/track/#{track.id.uuid}")
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

  def self.check_mbrainz_label(lccn_label, mbrainz_label)
    lccn_label.each do | l_label |
      return true if l_label.downcase =~ /#{mbrainz_label.name.downcase}/ or mbrainz_label.name.downcase =~ /#{l_label.downcase}/
      mbrainz_label.aliases.each do | label_alias |
        return true if l_label.downcase =~ /#{label_alias.name.downcase}/ or label_alias.name.downcase =~ /#{l_label.downcase}/
      end
    end
    false
  end

  def self.resource_in_array?(resource, array)
    array.each do | r |
      if r.uri == resource.uri
        return true
      end
    end
    false
  end  
  
end