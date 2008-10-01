require "FileUtils"

module F4110ut #:nodoc:
  module Acts #:nodoc:
    
    # == acts_as_cacheable
    # Adds capability for caching query results to any ActiveRecord object.
    # Cached query results are stored as marshalled objects on the file system.
    # This differs from ActiveRecord query cache in that these results are available
    # across the entire application, and not just within the scope of a single action.
    #
    # == Example of usage:
    #
    #   class Book < ActiveRecord::Base
    #     acts_as_cacheable :cache_path => "/tmp/cache/queries",
    #       :queries => {
    #         :all_books => [:all, {:order => "created_on"}],
    #         :banned_books => [:all, {
    #           :select => "author, title",
    #           :conditions => "status = 'banned'",
    #           :order => "title" }
    #   end
    #
    #   class BooksController < ApplicationController
    #     cache_sweeper :book_sweeper, :only => [:create, :update, :destroy]
    #
    #     def list_all_books
    #       @books = Book.all_books
    #     end
    #
    #     def list_banned_books
    #       @books = Book.banned_books
    #     end
    #   end
    #
    #   class BookSweeper < ActionController::Caching::Sweeper
    #     observe Book
    #
    #     def after_create(book)
    #       Book.clear_cache
    #     end
    #
    #     def after_update(book)
    #       Book.clear_cache
    #     end
    #
    #     def after_destroy(book)
    #       Book.clear_cache
    #     end
    #   end
    #
    module Cacheable
      def self.included(base) #:nodoc:
        base.send :extend, ClassMethods
      end
    
      module ClassMethods
        
        #  Make the model cacheable.
        #  * Adds a public class method for easy searching for each named hash in the :queries option hash
        #  
        #  === Options
        #  * <tt>:cache_path</tt> - String
        #      Specify a custom route for saving the cache results on the file system.
        #      Defaults to RAILS_ROOT + "/tmp/cache/queries"
        #  * <tt>:queries</tt> - Hash
        #      Specify the find method names and query options.
        #      Options are passed as an array and can be any valid arguments for the ActiveRecord::Base#find method.
        #      
        #      Example:
        #        :cached => [:all, {:conditions => ["status = ?", status], :order => "created_on"}]
        #      
        #      In the example above, a new method 'cached' is added to the class.
        #      'cached' will find results for the object as specified in the argument array
        #      
        #      NOTICE:
        #        'find_cached' and 'clear_cache' are invalid method names
        #
        def acts_as_cacheable(options = {})
          send :extend, SingletonMethods  # extend additional class methods
          
          # set the inheritable attribute to be used across Cacheable modules
          write_inheritable_attribute :acts_as_cacheable_options, {
            :cache_path => options[:cache_path] || RAILS_ROOT + "/tmp/cache/queries",
            :queries => options[:queries] }
          class_inheritable_reader :acts_as_cacheable_options
          
          # if query options are specified, then add search methods to class
          unless options[:queries].blank?
            options[:queries].each_key do |query|
              unless Object.method_defined? query # do not create a method with this name if one already exists
                Object.class_eval <<-EOV
                  def #{query}
                    find_cached('#{query}')
                  end
                EOV
              end
            end
          end
          
          private
          
          # Load cached query results if they exist.
          # Store retrieved query results as marshalled data in a cache file.
          def find_cached(query)
            args = acts_as_cacheable_options[:queries][query.to_sym]
            dir = acts_as_cacheable_options[:cache_path]
            path = dir  + "/" + query
            
            if File.exists?(path)
              cache = File.open path, 'r'
              result = Marshal.load(cache.read)
            else
              # create directories and file
              FileUtils.mkdir_p dir
              FileUtils.touch path
              
              result = find(*args)
              cache = File.open path, 'w'
              cache.puts Marshal.dump(result)
            end
            cache.close

            return result
          end
        end
      end

      module SingletonMethods
        
        # Use in a sweeper class to expire cached queries.
        #
        #   after_update(book)
        #     Book.clear_cache
        #   end
        def clear_cache
          dir = acts_as_cacheable_options[:cache_path]
          acts_as_cacheable_options[:queries].each_key do |query|
            path = dir  + "/" + query.to_s
            FileUtils.rm path if File.exists?(path)
          end
        end
      end
    end
  end
end