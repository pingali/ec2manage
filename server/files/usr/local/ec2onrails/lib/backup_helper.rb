###############################################################
# Extend S3 helper to list keys 
###############################################################
module Ec2onrails
  class S3Helper 

    def list_keys_2(filename_prefix = "incremental")
      AWS::S3::Bucket.objects(@bucket, :prefix => filename_prefix).collect{|obj| obj.key}
    end

    def delete_files_2(filename_prefix)
      list_keys_2(filename_prefix).each do |k|
        #puts " from delete_files_2: prefix = #{filename_prefix} key = #{k}"
        AWS::S3::S3Object.delete(k, @bucket)
      end
    end

    def list_keys_zrm(filename_prefix = "zrm/incremental")
      AWS::S3::Bucket.objects(@bucket, :prefix => filename_prefix).collect{|obj| obj.key}
    end

    def delete_files_zrm(filename_prefix)
      list_keys_2(filename_prefix).each do |k|
        puts " from delete_files_zrm: prefix = #{filename_prefix} key = #{k}"
        AWS::S3::S3Object.delete(k, @bucket)
      end
    end
  end
end

###############################################################
# Extract the last N keys to be removed
###############################################################
module Ec2onrails 
  module Utils
    
    # Sort the backups by time and get the last n
    def self.extract_keys_to_be_removed(keys, num_to_keep) 
      
      unless keys and !keys.empty? 
        return []
      end
      
      unless num_to_keep and keys.size > num_to_keep 
          return [] 
      end

      filtered_key_list = {} 
      keys.each do |k| 
        
        #incremental/backup-2009-03-07-02-20/all-ec2-72-44-59-75/mysql..000250
        arr = k.split(/\//)
        
        # "backup-2009-03-07-01-55"
        datetime = arr[1]
        
        # backup-2009-03-07-01-55 => 
        #       [
        #          "incremental/backup-2009-03-07-01-55/...mysql-bin.000245", 
        #          "incremental/backup-2009-03-07-01-55/....status.txt"
        #       ]
        if filtered_key_list[datetime]
          filtered_key_list[datetime] << k
        else 
          filtered_key_list[datetime] = [ k ]
        end
      end
      
      # Print the filtered key list
      #filtered_key_list.keys.each do |k| 
      #  puts "Keys => #{k}" 
      #end
      
      # Reverse sort the filtered keys
      sorted_filtered_keys = filtered_key_list.keys.sort { |x,y| y <=> x }
      
      #sorted_filtered_keys.each do |k| 
      #  puts "Sorted Keys => #{k}" 
      #end
      
      # Now extract the final list of keys 
      final_key_list = []
      range = (num_to_keep)..(sorted_filtered_keys.size)
      
      #puts "Range = #{range}" 

      # Extract the last N
      sorted_filtered_keys[range].each do |k|
        final_key_list.concat(filtered_key_list[k])
      end
      
      #final_key_list.each do |f| 
      #  puts f
      #end
      
      final_key_list
      
    end

    # Sort the backups by time and get the last n
    def self.extract_keys_to_be_removed_zrm(keys, num_to_keep) 
      
      unless keys and !keys.empty? 
        return []
      end
      
      unless num_to_keep and keys.size > num_to_keep 
          return [] 
      end
      
      #puts keys.inspect 

      #zrm/ec2manage-incremental/20090326061240/index
      #zrm/ec2manage-incremental/20090326061240/zrm_checksum
      #zrm/ec2manage-incremental/20090326061240/backup-data

      filtered_key_list = {} 
      keys.each do |k| 
        
        arr = k.split(/\//)
        
        #puts arr[0].inspect 

        backupset = arr[1]
        datetime  = arr[2] 
        
        # 20090326061240 => 
        #       [
        #         "zrm/ec2manage-incremental/20090326061240/index",
        #         "zrm/ec2manage-incremental/20090326061240/zrm_checksum"
        #         "zrm/ec2manage-incremental/20090326061240/backup-data"
        #       ]
        if filtered_key_list[datetime]
          filtered_key_list[datetime] << k
        else 
          filtered_key_list[datetime] = [ k ]
        end
      end
      
      # Print the filtered key list
      #filtered_key_list.keys.each do |k| 
      #  puts "Keys => #{k}" 
      #end
      
      # Reverse sort the filtered keys
      sorted_filtered_keys = filtered_key_list.keys.sort { |x,y| y <=> x }
      
      #sorted_filtered_keys.each do |k| 
      #  puts "Sorted Keys => #{k}" 
      #end
      
      # Now extract the final list of keys 
      final_key_list = []
      
      if (sorted_filtered_keys.size > num_to_keep) 
        range = (num_to_keep)..(sorted_filtered_keys.size)
      
        puts "Range = #{range}" 

        # Extract the last N
        sorted_filtered_keys[range].each do |k|
          final_key_list.concat(filtered_key_list[k])
        end
      end
      
      #final_key_list.each do |f| 
      #  puts f
      #end
      
      final_key_list
      
    end
  end
end

# Test code...
#keys =
#["incremental/backup-2009-03-07-01-55/all-ec2-72-44-59-75/mysql-bin.000245",
#"incremental/backup-2009-03-07-01-55/all-ec2-72-44-59-75/status.txt",
#"incremental/backup-2009-03-07-02-00/all-ec2-72-44-59-75/mysql-bin.000246",
#"incremental/backup-2009-03-07-02-00/all-ec2-72-44-59-75/status.txt",
#"incremental/backup-2009-03-07-02-05/all-ec2-72-44-59-75/mysql-bin.000247",
#"incremental/backup-2009-03-07-02-05/all-ec2-72-44-59-75/status.txt",
#"incremental/backup-2009-03-07-02-10/all-ec2-72-44-59-75/mysql-bin.000248",
#"incremental/backup-2009-03-07-02-10/all-ec2-72-44-59-75/status.txt",
#"incremental/backup-2009-03-07-02-15/all-ec2-72-44-59-75/mysql-bin.000249",
#"incremental/backup-2009-03-07-02-15/all-ec2-72-44-59-75/status.txt",
#"incremental/backup-2009-03-07-02-20/all-ec2-72-44-59-75/mysql-bin.000250",
#"incremental/backup-2009-03-07-02-20/all-ec2-72-44-59-75/status.txt",
#"incremental/backup-2009-03-07-02-25/all-ec2-72-44-59-75/mysql-bin.000251",
#"incremental/backup-2009-03-07-02-25/all-ec2-72-44-59-75/status.txt",
#"incremental/backup-2009-03-07-02-30/all-ec2-72-44-59-75/mysql-bin.000252",
#"incremental/backup-2009-03-07-02-30/all-ec2-72-44-59-75/status.txt",
#"incremental/backup-2009-03-07-02-35/all-ec2-72-44-59-75/mysql-bin.000253",
#"incremental/backup-2009-03-07-02-35/all-ec2-72-44-59-75/status.txt",
#"incremental/backup-2009-03-07-02-40/all-ec2-72-44-59-75/mysql-bin.000254",
#"incremental/backup-2009-03-07-02-40/all-ec2-72-44-59-75/status.txt",
#"incremental/backup-2009-03-07-02-41/all-ec2-72-44-59-75/mysql-bin.000255",
#"incremental/backup-2009-03-07-02-41/all-ec2-72-44-59-75/status.txt",
#"incremental/backup-2009-03-07-02-45/all-ec2-72-44-59-75/mysql-bin.000256",
#"incremental/backup-2009-03-07-02-45/all-ec2-72-44-59-75/status.txt",
#"incremental/backup-2009-03-07-02-50/all-ec2-72-44-59-75/mysql-bin.000257",
#"incremental/backup-2009-03-07-02-50/all-ec2-72-44-59-75/status.txt"]
#
#updated_keys = Ec2onrails::Utils.extract_keys_to_be_removed(keys, 5) 
#puts updated_keys.inspect 
#
#
#updated_keys = Ec2onrails::Utils.extract_keys_to_be_removed([], 5) 
#puts updated_keys.inspect 
#


## Test code...
#keys =[
#"zrm/ec2manage-incremental1/20090326061240/index",
#"zrm/ec2manage-incremental1/20090326061240/zrm_checksum",
#"zrm/ec2manage-incremental1/20090326061240/backup-data",
#"zrm/ec2manage-incremental1/20090326054649/index",
#"zrm/ec2manage-incremental1/20090326054649/zrm_checksum",
#"zrm/ec2manage-incremental1/20090326054649/backup-data",
#"zrm/ec2manage-incremental1/20090328022104/index",
#"zrm/ec2manage-incremental1/20090328022104/zrm_checksum",
#"zrm/ec2manage-incremental1/20090328022104/backup-data",
#"zrm/ec2manage-incremental1/20090326064631/index",
#"zrm/ec2manage-incremental1/20090326064631/zrm_checksum",
#"zrm/ec2manage-incremental1/20090326064631/backup-data",
#"zrm/ec2manage-incremental1/20090326052742/index",
#"zrm/ec2manage-incremental1/20090326052742/zrm_checksum",
#"zrm/ec2manage-incremental1/20090326052742/backup-data",
#"zrm/ec2manage-incremental1/20090326054532/index",
#"zrm/ec2manage-incremental1/20090326054532/zrm_checksum",
#"zrm/ec2manage-incremental1/20090326054532/backup-data",
#"zrm/ec2manage-incremental1/20090328023539/index",
#"zrm/ec2manage-incremental1/20090328023539/zrm_checksum",
#"zrm/ec2manage-incremental1/20090328023539/backup-data",
#"zrm/ec2manage-incremental1/20090326060445/index",
#"zrm/ec2manage-incremental1/20090326060445/zrm_checksum",
#"zrm/ec2manage-incremental1/20090326060445/backup-data",
#"zrm/ec2manage-incremental1/20090326064535/index",
#"zrm/ec2manage-incremental1/20090326064535/zrm_checksum",
#"zrm/ec2manage-incremental1/20090326064535/backup-data",
#"zrm/ec2manage-incremental1/20090326060516/index",
#"zrm/ec2manage-incremental1/20090326060516/zrm_checksum",
#"zrm/ec2manage-incremental1/20090326060516/backup-data",
#"zrm/ec2manage-incremental1/20090328022124/index",
#"zrm/ec2manage-incremental1/20090328022124/zrm_checksum",
#"zrm/ec2manage-incremental1/20090328022124/backup-data",
#"zrm/ec2manage-incremental1/20090326054937/index",
#"zrm/ec2manage-incremental1/20090326054937/zrm_checksum",
#"zrm/ec2manage-incremental1/20090326054937/backup-data",
#"zrm/ec2manage-incremental1/20090326060241/index",
#"zrm/ec2manage-incremental1/20090326060241/zrm_checksum",
#"zrm/ec2manage-incremental1/20090326060241/backup-data",
#"zrm/ec2manage-incremental1/20090326060511/index",
#"zrm/ec2manage-incremental1/20090326060511/zrm_checksum",
#"zrm/ec2manage-incremental1/20090326060511/backup-data",
#"zrm/ec2manage-incremental1/20090326054914/index",
#"zrm/ec2manage-incremental1/20090326054914/zrm_checksum",
#"zrm/ec2manage-incremental1/20090326054914/backup-data"
#]
#
#updated_keys = Ec2onrails::Utils.extract_keys_to_be_removed_zrm(keys, 5) 
#puts updated_keys.inspect 
#
#
#updated_keys = Ec2onrails::Utils.extract_keys_to_be_removed_zrm([], 5) 
#puts updated_keys.inspect 
#
