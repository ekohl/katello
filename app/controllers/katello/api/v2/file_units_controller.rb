module Katello
  class Api::V2::FileUnitsController < Api::V2::ApiController
    apipie_concern_subst(:a_resource => N_("a file"), :resource => "files")
    include Katello::Concerns::Api::V2::RepositoryContentController

    def default_sort
      %w(name asc)
    end

    private

    def repo_association
      :repository_id
    end
  end
end
