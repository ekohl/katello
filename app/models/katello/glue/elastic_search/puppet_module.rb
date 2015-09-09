module Katello
  module Glue::ElasticSearch::PuppetModule
    extend ActiveSupport::Concern

    included do
      include Glue::ElasticSearch::BackendIndexedModel
    end

    def index_options
      {
        "_type"             => :puppet_module,
        "name_sort"         => name.downcase,
        "name_autocomplete" => name,
        "author_autocomplete" => author,
        "sortable_version_sort"  => sortable_version
      }
    end

    module ClassMethods
      def index_settings
        {
          "index" => {
            "analysis" => {
              "filter" => Util::Search.custom_filters,
              "analyzer" => Util::Search.custom_analyzers
            }
          }
        }
      end

      def index_mapping
        {
          :puppet_module => {
            :properties => {
              :id               => { :type => 'string', :index    => :not_analyzed },
              :name             => { :type => 'string', :analyzer => :kt_name_analyzer },
              :name_sort        => { :type => 'string', :index    => :not_analyzed },
              :sortable_version => { :type => 'string', :index    => :not_analyzed },
              :sortable_version_sort => { :type => 'string', :index    => :not_analyzed },
              :repoids          => { :type => 'string', :index    => :not_analyzed }
            }
          }
        }
      end

      def index
        "#{Katello.config.elastic_index}_puppet_module"
      end

      def search_type
        :puppet_module
      end

      def autocomplete_name(query, repoids = nil, page_size = 15)
        return [] unless Tire.index(self.index).exists?

        query = autocomplete_field_query("name", query)
        field_search(query, :name, repoids, page_size)
      end

      def autocomplete_author(query, repoids = nil, page_size = 15, name = nil)
        return [] unless Tire.index(self.index).exists?

        query = autocomplete_field_query("author", query)
        if name.present?
          query += " AND #{autocomplete_field_query("name", name)}"
        end

        field_search(query, :author, repoids, page_size)
      end

      def id_search(ids)
        return Util::Support.array_with_total unless Tire.index(self.index).exists?
        search = PuppetModule.search do
          fields [:id, :name, :repoids]
          query do
            all
          end
          size ids.size
          filter :terms, :id => ids
        end
        search.to_a
      end

      def module_count(repos)
        return Util::Support.array_with_total unless index_exists?
        repo_ids = repos.map(&:pulp_id)
        search = PuppetModule.search do
          query do
            all
          end
          fields [:id]
          size 1
          filter :terms, :repoids => repo_ids
        end
        search.total
      end

      # Find the 'latest' version of the puppet modules provided across
      # the list of repos provided.
      def latest_modules_search(names_and_authors, repoids)
        return Util::Support.array_with_total unless Tire.index(self.index).exists?

        # use multi-search to perform a single request to elasticsearch which
        # will perform N queries/searches
        multi_search = PuppetModule.multi_search do
          names_and_authors.each do |item|
            search do
              query do
                string "name:#{ item[:name] } author:#{ item[:author] }", :default_operator => 'AND'
              end
              size 1
              filter :terms, :repoids => repoids
              sort { by :sortable_version, "desc" }
            end
          end
        end

        # multi_search will return a result set for each query.
        # since each query will have a single document, return a list of those individual results
        multi_search.reject { |results| results[0].nil? }.map { |results| results[0] }
      end

      def exists?(options)
        results = PuppetModule.latest_modules_search([{ :name => options[:name],
                                                        :author => options[:author] }],
                                                     options[:repoids])
        results.present?
      end

      def search(_options = {}, &block)
        Tire.search(self.index, &block).results
      end

      def multi_search(_options = {}, &block)
        Tire.multi_search(self.index, &block).results
      end

      def mapping
        Tire.index(self.index).mapping
      end

      # TODO: break up method
      # rubocop:disable MethodLength
      def legacy_search(query, options = {})
        options = {:start => 0,
                   :page_size => 10,
                   :repoids => nil,
                   :sort => [:name_sort, "asc"],
                   :search_mode => :all,
                   :default_field => 'name',
                   :fields => [],
                   :filters => nil}.merge(options)
        options[:repoids] = Array(options[:repoids])

        if !Tire.index(self.index).exists? || (options[:repoids] && options[:repoids].empty?)
          return Util::Support.array_with_total
        end

        all_rows = query.blank? #if blank, get all rows
        search = Tire::Search::Search.new(self.index)
        search.instance_eval do
          query do
            if all_rows
              all
            else
              string query,  :default_field => options[:default_field]
            end
          end

          fields options[:fields] unless options[:fields].blank?

          if options[:page_size] > 0
            size options[:page_size]
            from options[:start]
          end
          sort { by options[:sort][0], options[:sort][1] } if all_rows
        end

        if options[:filters]
          options[:filters].each do |filter|
            search.filter(filter.keys.first, filter.values.first)
          end
        end

        if options[:repoids]
          Util::Package.setup_shared_unique_filter(options[:repoids], options[:search_mode], search)
        end

        return search.perform.results
      rescue Tire::Search::SearchRequestFailed
        Util::Support.array_with_total
      end

      def index_puppet_modules(puppet_module_ids)
        puppet_modules = puppet_module_ids.collect do |module_id|
          puppet_module = self.find(module_id)
          puppet_module.as_json.merge(puppet_module.index_options)
        end

        unless puppet_modules.empty?
          create_index
          Tire.index Katello::PuppetModule.index do
            import puppet_modules
          end
        end
      end

      def field_search(query, field, repoids = nil, page_size = 15)
        search = Tire.search(self.index) do
          fields [field]
          query do
            string query
          end

          if repoids
            filter :terms, :repoids => repoids
          end
        end

        return search.results.map(&field).uniq[0, page_size.to_i]
      end

      def autocomplete_field_query(field, value)
        value = "*" if value.blank?
        value = Util::Search.filter_input(value)
        "#{field}_autocomplete:(#{value})"
      end

      def add_indexed_repoid(puppet_module_ids, repoid)
        update_array(puppet_module_ids, 'repoids', [repoid], [])
      end

      def remove_indexed_repoid(puppet_module_ids, repoid)
        update_array(puppet_module_ids, 'repoids', [], [repoid])
      end
    end
  end
end