class Playlist < ActiveRecord::Base
  has_many :playlist_songs
  has_many :songs, through: :playlist_songs

  ALL_GENRES = ["rock", "jazz", "pop", "rap", "country", "classical", "blues", "metal", "gospel", "punk", "indie"]
  attr_accessor :genres

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

    if (attributes == [])
      #No attributes returns a randomized playlist
      return self.random_playlist(p_name, input_length)
    else
      assign = self.assign_features_and_genres(attributes)
      feature_query = assign[0]
      genre_query = assign[1]
      specified_genres = assign[2]

      #Step 2
      search = self.search_songs(feature_query, genre_query, input_length)

      if (search.length <= 0)
        puts "Couldn't satisfy query"
      else
        #Step 5
        search = search.sample(input_length)
        playlist = Playlist.create
        search.each do |song|
          playlist.add_song(song)
        end
        playlist.name = p_name
        playlist.establish_genres(specified_genres)
        playlist.save
        return playlist
      end
    end
  end

  def self.assign_features_and_genres(attributes)
    #read through attributes
    #outputs two query arrays (features and genres) and one array to assign genres to memory
    feature_query = []
    genre_query = []
    specified_genres = []
    features = {"acoustic" => "acousticness >= 0.6",
                "dancing" => "danceability >= 0.6",
                "energetic" => "energy >= 0.6",
                "chill" => "energy <= 0.4",
                "live" => "liveness >= 0.6",
                "lyrical" => "instrumentalness <= 0.4",
                "fast" => "tempo >= 125.0",
                "slow" => "tempo <= 115.0",
                "happy" => "valence >= 0.6",
                "melancholy" => "valence <= 0.4"}
    # Step 1
    attributes.each do |attribute|
      if features.keys.include?(attribute)
        feature_query << features[attribute]
      elsif ALL_GENRES.include?(attribute)
        genre_query << "genre = '#{attribute}'"
        specified_genres << attribute
      end
    end
    feature_query.uniq!
    genre_query.uniq!
    return [feature_query, genre_query, specified_genres]
  end
  def self.search_songs(feature_query, genre_query, input_length)
    #helper method for generate
    #Execute a narrowing search
    query_string = self.build_query(feature_query, genre_query)
    search = []
    #Step 3
    search.concat(Song.where(query_string))
    search.uniq!
    if (search.length < input_length)
      query_size = feature_query.length
      feature_query.each do |query|
        query = query.sub("4", "5").sub("6", "5")
      end
      query_string = self.build_query(feature_query, genre_query)
      search.concat(Song.where(query_string))

      while (query_size > 0)
        break if (search.length >= input_length)
        #Step 4
        query_size -= 1
        new_queries = feature_query.combination(query_size).to_a
        new_queries.each do |query|
          query_string = self.build_query(query, genre_query)
          search.concat(Song.where(query_string))
          search.uniq!
          if search.length >= input_length
            search = search[0...input_length]
            break
          end
        end
      end
    end
    return search
  end
  def self.random_playlist(name, input_length)
    playlist = Playlist.create(name: name)
    list = Song.all.sample(input_length)
    list.each do |song|
      playlist.add_song(song)
    end
    playlist.save()
    return playlist
  end

  def self.build_query(feature_query, genre_query)
    #helper method for generate
    #final form: "attr > .5 AND attr2 <= .4 AND (genre = genre1 OR genre = genre2)
    query_string = ""
    genre_string = ""

    feature_query.each do |q|
      #Non-genre specifications should require AND
      if (query_string.length > 0)
        query_string += " AND "
      end
      query_string += q
    end
    genre_query.each do |g|
      if (genre_string.length > 0)
        genre_string += " OR "
      end
      genre_string += g
    end
    #Return combined string
    if (genre_query.length > 0 && feature_query.length > 0)
      return_string = "#{query_string} AND (#{genre_string})"
    else
      #If one of the strings is empty, return the full one
      return_string = (feature_query.length == 0 ? genre_string : query_string)
    end
    return_string
  end

  def establish_genres(attributes)
    @genres = []
    if (attributes == nil || attributes == [])
      @genres = ALL_GENRES
    else
      @genres = attributes.uniq
    end
  end

  def genres
    #genre currently does not persist, meaning this model will not work with loaded playlists without developing a genre model
    if (@genres == nil || @genres == [])
      @genres = ALL_GENRES
    end
    #returns all unique genres as an array of strings
    #unique_genres = self.songs.map { |song| song.genre }.uniq!.sort
    @genres.uniq
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

  def optimize(feature, increment, percent = 0.25)
    #improve the playlist based on the feature

    #Arguments:
    #feature -- The column name, passed as a symbol or string (string or symbol)
    #percent -- The max percent of the playlist willing to replace (float, less than zero)
    #increment -- Whether one would like to make the playlist "more"(true) feature or "less"(false)

    #Steps:
    #1. establish "evaluator" and "remove_value" based on whether the function is increasing or decreasing and average value
    #2. begin a loop. The loop breaks when the average has been sufficiently raised or when too many songs have been replaced
    #3. run #get_better_songs, which will return an array of songs which would improve the playlist
    #4. Add a random song from the #get_better_songs array, and remove the words
    #    ---> If the #get_better_songs return value is [], the playlist cannot be further optimized.
    #5. Save the playlist and return a success string

    # Step 1
    evaluator = (increment ? ">" : "<")
    remove_value = (increment ? "first" : "last")
    loop_count = 0

    # Step 2
    loop do
      loop_count += 1

      # Step 3
      find = get_better_songs(feature, evaluator)
      #Step 4
      if (find.length > 0)
        song_to_add = find.sample(1).first
        add_song(song_to_add)
        # puts("Added #{song_to_add.title}")
        #Looks like remove (self.songs.in_order_by_danceability.first) or remove (self.songs.in_order_by_energy.last)
        del_song = self.songs.order(feature).send(remove_value)
        delete_song(del_song)
        # puts("Deleted #{del_song.title}")
      else
        self.save
        puts "Playlist is already optimized"
        return self
      end

      break if (feature_is_sufficient?(feature, increment) || loop_count >= songs.length * percent)
    end
    #Step 5
    #puts "Playlist has been optimized. #{loop_count} songs have been replaced."
    self.save
    return self
  end

  def get_better_songs(feature, evaluator)
    #helper method for optimize
    #Returns an array of songs that would raise the average
    #Will not add songs already in the playlist or outside defined genres
    #may return an empty array-indicating the playlist cannot be optimized further
    avg = average(feature)
    query = "#{feature} #{evaluator} #{avg}"
    find = Song.where(query)
    find = find.select { |song| self.genres.include?(song.genre) && !self.songs.include?(song) }
    find
  end

  def feature_is_sufficient?(feature, increment)
    # Determines if the average of a feature is sufficient to be considered of that tag
    # argument "increment" is boolean, true determines if the value is sufficiently high, false sufficiently low

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

  def ordered_playlist_songs
    self.playlist_songs.order(:playlist_index)
  end

  def renumber
  end

  def change_index(old_index, new_index)
    if valid_index?(old_index) && valid_index?(new_index) && old_index != new_index
      # gets the PlaylistSong index of the song to be moved
      changed_song = self.playlist_songs.find_by(playlist_index: old_index)
      if old_index > new_index
        # gets an array of songs affected by the shift
        songs_to_shift = self.ordered_playlist_songs[(new_index - 1)..(old_index - 1)]
        songs_to_shift.each { |song| song.down_index }
      elsif old_index < new_index
        # gets an array of songs affected by the shift
        songs_to_shift = self.ordered_playlist_songs[(old_index - 1)..(new_index - 1)]
        songs_to_shift.each { |song| song.up_index }
      end
      # update song's playlist_index
      changed_song.playlist_index = new_index
      changed_song.save
    end
    return self
  end
end
