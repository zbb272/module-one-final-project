class Playlist < ActiveRecord::Base
  has_many :playlist_songs
  has_many :songs, through: :playlist_songs

  def self.generate(p_name, attributes, input_length)
    #search through Songs and narrow by each attribute (passed in CLI by tags)
    #Arguments:
    # p_name-Name of Playlist(string),
    # attributes-Array of attributes(strings),
    # input_length--desired length of playlist(integer)

    #Steps:
    # 1. Construct an array of SQL query-snippets based on attributes
    # 2. Assemble a query using #build_query
    # 3. Search the Database using query
    # 4. Using Array#combination, expand query until search results match or surpass input_length
    # 5. Create the Playlist instance, add its songs directly, save, and return it
    list = []
    query = []
    # Step 1
    attributes.each do |attribute|
      if (attribute == "acoustic")
        query << "acousticness >= 0.6"
      elsif (attribute == "dancing")
        query << "danceability >= 0.6"
      elsif (attribute == "energetic")
        query << "energy >= 0.6"
      elsif (attribute == "chill")
        query << "energy <= 0.4"
      elsif (attribute == "live")
        query << "liveness >= 0.6"
      elsif (attribute == "lyrical")
        query << "speechiness >= 0.6"
      elsif (attribute == "fast")
        query << "tempo >= 125.0"
      elsif (attribute == "slow")
        query << "tempo <= 115.0"
      elsif (attribute == "happy")
        query << "valence >= 0.6"
      elsif (attribute == "melancholy")
        query << "valence <= 0.4"
      elsif (attribute == "rock")
        query << "genre = 'rock'"
      elsif (attribute == "jazz")
        query << "genre = 'jazz'"
      elsif (attribute == "pop")
        query << "genre = 'pop'"
      elsif (attribute == "country")
        query << "genre = 'country'"
      elsif (attribute == "classical")
        query << "genre = 'classical'"
      else
        puts "Attribute Not Found"
      end
    end
    # ----------------------------
    # BEGIN REFACTOR
    # ----------------------------
    # {"acoustic"=>"acousticness >= 0.6"}

    # attributes.each do |attribute|
    #   string += new_hash[attribute] if new_hash[attribute]
    # end

    # -----------------------------
    # END REFACTOR
    # -----------------------------
    query.uniq!
    search = []
    #Step 2
    query_string = self.build_query(query)
    #Step 3
    search.concat(Song.where(query_string))
    search.uniq!
    query_size = query.length
    while (query_size > 0)
      if (search.length < input_length)
        #Step 4
        query_size -= 1
        new_queries = query.combination(query_size).to_a
        new_queries.each do |query|
          query_string = self.build_query(query)
          search.concat(Song.where(query_string))
          search.uniq!
        end
      else
        break
      end
    end

    if (search.length <= 0)
      puts "Couldn't satisfy query"
    else
      search = search.sample(input_length)
      #Step 5
      playlist = Playlist.create
      search.each do |song|
        playlist.add_song(song)
      end
      playlist.name = p_name
      playlist.save
      return playlist
    end
  end

  def self.build_query(query)
    #helper method for generate
    #final form: "attr > .5 AND attr2 <= .4 AND (genre = genre1 OR genre = genre2)
    query_string = ""
    genre_string = ""

    query.each do |q|
      if q[0] == "g"
        #Each song in the db has exactly one genre, so the query should search for these with OR
        if (genre_string.length > 0)
          genre_string += " OR "
        end
        genre_string += q
      else
        #Non-genre specifications should require AND
        if (query_string.length > 0)
          query_string += " AND "
        end
        query_string += q
      end
    end
    if (genre_string != "")
      return_string = "#{query_string} AND (#{genre_string})"
    else
      return_string = query_string
    end
    return_string
  end

  def genres
    #returns all unique genres as an array of strings
    return songs.map { |song| song.genre }.uniq!
  end

  def average(feature)
    #returns an average based on quality
    #only for float qualities, passed as symbols
    #eg: my_playlist.average(:danceability)
    return_value = self.songs.inject(0) { |sum, song| sum + song.send("#{feature}") }
    return_value / self.songs.length
  end

  def get_averages
    #return a hash of averageable data
    relevant_columns = Song.columns.select do |col|
      col.type == :float
    end
    average_hash = {}
    relevant_columns.each do |col|
      average_hash[col.name] = self.average(col.name)
    end
    average_hash
  end

  def get_data
    #return a hash including the name and relevant data
    return_hash = {name: self.name, length: self.songs.length, data: self.get_averages}
  end

  def distribution_by_feature(feature)
    #ideally for pie charts, returns a count
    #postitive: songs whose :feature is >= .6
    #negative: songs whose :feature is <= .4
    #neutral: songs whose :feature is between .4 and .6
    return_hash = {positive: 0, negative: 0, neutral: 0}
    self.songs.each do |song|
      if feature_is_sufficient?(feature, true)
        return_hash[:positive] += 1
      elsif feature_is_sufficient?(feature, false)
        return_hash[:negative] += 1
      else
        return_hash[:neutral] += 1
      end
    end

    return_hash
  end

  def optimize(feature, percent = 0.25, increment)
    #improve the playlist based on the feature

    #Arguments:
    #feature -- The column name, passed as a symbol or string (Prefferably symbol)
    #percent -- The max percent of the playlist willing to replace (float, less than zero)
    #increment -- Whether one would like to make the playlist "more"(true) feature or "less"(false)

    #Steps:
    #1. establish "evaluator" and "remove_value" based on whether the function is increasing or decreasing and average value
    #2. begin a loop
    #3. determine the worst song by feature and remove it
    #4. construct an SQL query amounting to something like "WHERE feature < 0.4546"
    #5. find all songs meeting the query and narrow them down by genres already in the playlist.
    #6. select a random song from the results and add it
    #7. continue the loop until the feature is acheived or until the given percentage of songs have been replaced (default 25%)

    # Step 1
    evaluator = (increment ? ">" : "<")
    remove_value = (increment ? "first" : "last")
    loop_count = 0
    # Step 2
    loop do
      avg = average(feature)
      # Step 3
      del_song = self.songs.order(feature).send(remove_value)
      puts ("Removing #{del_song.title}: #{del_song.send("#{feature}")}")
      delete_song(del_song)
      puts ("Removed")
      # Step 4
      query = "#{feature} #{evaluator} #{avg}"

      # Step 5 Daisiest Chain: Selects a random song that fits the feature specs and falls within a relevant genre
      find = Song.where(query).select { |song| self.genres.include?(song.genre) }.sample(1).first
      # Step 6
      puts ("Adding #{find.title}: #{find.send("#{feature}")}")
      add_song(find)
      puts ("Added")

      loop_count += 1

      puts ("Total #{loop_count}")
      # Step 7
      break if (feature_is_sufficient?(feature, increment) || loop_count >= songs.length * percent)
    end
  end

  def feature_is_sufficient?(feature, increment)
    # Determines if the average of a feature is sufficient to be considered of that tag
    # argument "increment" is boolean, true determines if the value is sufficiently high, false sufficiently low
    #

    evaluator = (increment ? ">= 0.6" : "<= 0.4")
    if (feature == :tempo)
      evaluator = (increment ? ">=125" : "<=115")
    end

    return eval("#{self.average(feature)} #{evaluator}")
  end

  # add_song
  def add_song(song)
    # adds song to playlist and creates index based on number of
    # songs in the playlist
    self.songs << song
    song_in_playlist = self.playlist_songs.last
    song_in_playlist.playlist_index = self.playlist_songs.length
    song_in_playlist.save
  end

  # delete_song
  def delete_song(song)
    # gets the index of the song to be deleted
    # this should be refactored with a Song#get_playlist_index method
    deleted_index = self.playlist_songs.find_by(song_id: song.id).playlist_index
    # deletes song and reorders remaining tracks
    self.songs.delete(song)
    self.playlist_songs.reorder_from_index(deleted_index)
  end

  # order_playlist
  def order_playlist
    # returns an array of songs in index order
    playlist_songs = self.playlist_songs.order(:playlist_index)
    playlist_songs.map { |playlist_song| playlist_song.song }
  end

  # shuffle_song
  def shuffle_songs
    # shuffles songs and returns playlist
    shuffled_songs = self.playlist_songs.shuffle
    shuffled_songs.each_with_index do |song, index|
      song.playlist_index = index + 1
      song.save
    end
    self
  end

  def valid_index?(playlist_index)
    playlist_index <= self.playlist_songs.length && playlist_index > 0
  end

  def change_index(old_index, new_index)
    if valid_index?(old_index) && valid_index?(new_index) && old_index != new_index
      # gets the PlaylistSong index of the song to be moved
      changed_song = self.playlist_songs.find_by(playlist_index: old_index)
      if old_index > new_index
        # gets an array of songs affected by the shift
        songs_to_shift = self.ordered_playlist_songs[(new_index-1)..(old_index-1)]
        songs_to_shift.each {|song| song.down_index}
      elsif old_index < new_index
        # gets an array of songs affected by the shift
        songs_to_shift = self.ordered_playlist_songs[(old_index-1)..(new_index-2)]
        songs_to_shift.each {|song| song.up_index}
      end
      # update song's playlist_index
      changed_song.playlist_index = new_index
      changed_song.save
    end
    return self
  end
end
