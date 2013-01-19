class BigbluebuttonRecording < ActiveRecord::Base
  belongs_to :room, :class_name => 'BigbluebuttonRoom'

  validates :recordid,
            :presence => true,
            :uniqueness => true

  attr_accessible :recordid, :meetingid, :name, :published, :start_time,
                  :end_time, :room_id

  has_many :metadata,
           :class_name => 'BigbluebuttonMetadata',
           :foreign_key => 'recording_id',
           :dependent => :destroy

  has_many :playback_formats,
           :class_name => 'BigbluebuttonPlaybackFormat',
           :foreign_key => 'recording_id',
           :dependent => :destroy

  def to_param
    self.recordid
  end

  # Syncs the recordings in the db with the array of recordings in 'recordings',
  # as received from BigBlueButtonApi#get_recordings.
  # Will add new recordings that are not in the db yet and update the ones that
  # already are (matching by 'recordid'). Will NOT delete recordings from the db,
  # even if they are not in the array.
  # TODO: catch exceptions on creating/updating recordings
  def self.sync(recordings)
    recordings.each do |rec|
      rec_obj = BigbluebuttonRecording.find_by_recordid(rec[:recordID])
      rec_data = adapt_recording_hash(rec)
      if rec_obj
        self.update_recording(rec_obj, rec_data)
      else
        self.create_recording(rec_data)
      end
    end
  end

  protected

  # Adapt keys in 'hash' from bigbluebutton-api-ruby's format to ours
  def self.adapt_recording_hash(hash)
    new_hash = hash.clone
    mappings = {
      :recordID => :recordid,
      :meetingID => :meetingid,
      :startTime => :start_time,
      :endTime => :end_time
    }
    new_hash.keys.each { |k| new_hash[ mappings[k] ] = new_hash.delete(k) if mappings[k] }
    new_hash
  end

  # Updates the BigbluebuttonRecording 'recording' with the data in the hash 'data'.
  # The format expected for 'data' follows the format returned by
  # BigBlueButtonApi#get_recordings but with the keys already converted to our format.
  def self.update_recording(recording, data)
    filtered = data.slice(:meetingid, :name, :published, :start_time, :end_time)
    recording.update_attributes(filtered)

    sync_additional_data(recording, data)
  end

  # Creates a new BigbluebuttonRecording with the data from 'data'.
  # The format expected for 'data' follows the format returned by
  # BigBlueButtonApi#get_recordings but with the keys already converted to our format.
  def self.create_recording(data)
    filtered = data.slice(:recordid, :meetingid, :name, :published, :start_time, :end_time)
    recording = BigbluebuttonRecording.create!(filtered)

    sync_additional_data(recording, data)
  end

  # Syncs data that's not directly stored in the recording itself but in
  # associated models (e.g. metadata and playback formats).
  # The format expected for 'data' follows the format returned by
  # BigBlueButtonApi#get_recordings but with the keys already converted to our format.
  def self.sync_additional_data(recording, data)
    sync_metadata(recording, data[:metadata]) if data[:metadata]
    if data[:playback] and data[:playback][:format]
      sync_playback_formats(recording, data[:playback][:format])
    end
  end

  # Syncs the metadata objects of 'recording' with the data in 'metadata'.
  # The format expected for 'metadata' follows the format returned by
  # BigBlueButtonApi#get_recordings but with the keys already converted to our format.
  def self.sync_metadata(recording, metadata)
    local_metadata = metadata.clone
    BigbluebuttonMetadata.where(:recording_id => recording.id).each do |data|
      # the metadata is in the hash, update it in the db
      if local_metadata.has_key?(data.name)
        data.update_attributes({ :content => local_metadata[data.name] })
        local_metadata.delete(data.name)
      # the format is not in the hash, remove from the db
      else
        data.destroy
      end
    end

    # for metadata that are not in the db yet
    local_metadata.each do |name, content|
      attrs = { :name => name, :content => content, :recording_id => recording.id }
      BigbluebuttonMetadata.create!(attrs)
    end
  end

  # Syncs the playback formats objects of 'recording' with the data in 'formats'.
  # The format expected for 'formats' follows the format returned by
  # BigBlueButtonApi#get_recordings but with the keys already converted to our format.
  def self.sync_playback_formats(recording, formats)
    formats_hash = formats.clone
    BigbluebuttonPlaybackFormat.where(:recording_id => recording.id).each do |format_db|
      # the format exists in the hash, update it in the db
      format = formats_hash.select{ |d| d[:type] == format_db.format_type }.first
      if format
        format_db.update_attributes({ :url => format[:url], :length => format[:length] })
        formats_hash.delete(format)
      # the format is not in the hash, remove from the db
      else
        format_db.destroy
      end
    end

    # for formats that are not in the db yet
    formats_hash.each do |format|
      attrs = { :recording_id => recording.id, :format_type => format[:type],
        :url => format[:url], :length => format[:length] }
      BigbluebuttonPlaybackFormat.create!(attrs)
    end
  end

end