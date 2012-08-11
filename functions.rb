def randomize(hash)
  a = 0
  hash[:len] ||= 10
  for i in 1..hash[:len]
    a *= 10
    a += rand(9)
  end
  return hash[:fn]+'_'+a.to_s
end

def build_fn(fn)
  ext = File.extname(fn)
  base = File.basename(fn, '.*')
  return randomize({:fn => base})+ext
end

def split_input(input)
  return input.split /[ *,*;*.*\/*]/
end

def tag_exists?(tag)
  if $sqlite
    list = $db.execute("select * from #{$tag_table} where tag = ?", tag)
  elsif $mongo
    list = $tag.find_one({:tag => tag}).to_a
  end
  return list.length > 0
end

def add_tag(tag)
  if $sqlite
    unless tag_exists? tag
      $db.execute("insert into #{$tag_table} values ( ? )", tag)
    end
    id = $db.execute("select oid from #{$tag_table} where tag = ?", tag)
    return id[0]
  elsif $mongo
    unless tag_exists? tag
      $tag.insert({:tag => tag})
    end
    id = $tag.find_one({:tag => tag})['_id'].to_s
    return id
  end
end

def add_tags(list)
  list.each {|tag|
    add_tag tag
  }
end

def insert_torrent(url, name, magnet)
  if $sqlite
    $db.execute("insert into #{$torrent_table} values ( ?, ?, ?, ? )", url, name, magnet, Time.now.to_i)
  elsif $mongo
    $torrent.insert({:url => url, :name => name, :magnet => magnet, :date => Time.now.to_i})
  end
end

def save_torrent(fn, tmp)
  File.open(File.join('public', $upload_dir, fn), 'w') do |f|
    f.write(tmp.read)
  end
end

def tag_id_by_name(tag)
  if $sqlite
    return $db.execute("select oid from #{$tag_table} where tag = ?", tag)
  elsif $mongo
    tags = $tag.find_one({:tag => tag})
    return tags
  end
end

def torrent_id_by_url(url)
  if $sqlite
    res = $db.execute("select oid from #{$torrent_table} where url = ?", url)
    return res[0][0]
  elsif $mongo
    return $torrent.find_one({:url => url})['_id'].to_s
  end
end

def latest_torrents(how_many=20)
  if $sqlite
    return $db.execute("select * from #{$torrent_table} order by date desc limit 0, ?", how_many)
  elsif $mongo
    return $torrent.find.sort([:date, :desc]).limit(how_many).to_a
  end
end

def make_tag_assoc(tag_id, torrent_id)
  if $sqlite
    $db.execute("insert into #{$map_table} values ( ?, ? )", tag_id, torrent_id)
  elsif $mongo
    $map.insert({:tag => tag_id, :torrent => torrent_id})
  end
end

def map_tags_to_torrents(taglist, url)
  torrent_id = torrent_id_by_url url
  taglist.each {|tag|
    tag_id = tag_id_by_name tag
    make_tag_assoc(tag_id, torrent_id)
  }
end

def build_arr(taglist)
  return "( #{taglist.join(', ')} )"
end

def tag_ids_from_names(tags)
  tag_ids = []
  tags.each {|tag|
    tag_ids.push(tag_id_by_name(tag))
  }
  tag_ids.flatten!
  return tag_ids
end

def urls_from_tag_ids(tag_ids)
  torrents = []
  if $sqlite
   torrent_ids = $db.execute("select torrent, count(*) num from #{$map_table} where tag in #{build_arr(tag_ids)} group by torrent having num = #{tag_ids.length}")
    torrent_ids.flatten.each do |torrent_id|
      a = $db.execute("select url,name,magnet from #{$torrent_table} where oid = ?", torrent_id).flatten
      torrent = {
        :url => a[0],
        :name => a[1],
        :magnet => a[2],
        :date => a[3]
      }
      torrents.push(torrent)
    end
  elsif $mongo
    torrent_ids = $map.find({:tag => {:$in => tag_ids}}).to_a
    torrent_ids.each do |torrent_id|
      a = $torrent.find_one({:_id => torrent_id}).to_a
      torrents.push(torrent)
    end
  end
  return torrents.uniq
end

def build_magnet_uri(fn)
  torrent = BEncode.load_file(fn)
  sha1 = OpenSSL::Digest::SHA1.digest(torrent['info'].bencode)
  p = {
    :xt => "urn:btih:" << Base32.encode(sha1),
    :dn => CGI.escape(torrent["info"]["name"])
  }
  Array(torrent["announce-list"]).each do |(tracker, _)|
    p[:tr] ||= []
    p[:tr] << tracker
  end
  magnet_uri  = "magnet:?xt=#{p.delete(:xt)}"
  magnet_uri << "&" << Rack::Utils.build_query(p)
  return magnet_uri
end

def get_torrent_name(fn)
  file = BEncode.load_file(fn)
  return file['info']['name']
end

