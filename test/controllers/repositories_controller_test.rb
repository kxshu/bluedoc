# frozen_string_literal: true

require "test_helper"

class RepositoriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:user)
    @group = create(:group)
  end

  test "GET /new" do
    assert_require_user do
      get "/new"
    end

    sign_in @user
    get "/new"
    assert_equal 200, response.status
  end

  test "POST /repositories" do
    assert_require_user do
      post "/repositories"
    end

    # with user
    sign_in @user
    repo = build(:repository)
    repo_params = {
      name: repo.name,
      slug: repo.slug,
      description: repo.description,
      privacy: "private",
      user_id: 1234,
    }
    post "/repositories", params: { repository: repo_params }
    assert_equal 403, response.status

    repo_params[:user_id] = @user.id
    post "/repositories", params: { repository: repo_params }
    assert_redirected_to "/#{@user.slug}/#{repo.slug}"

    created_repo = @user.repositories.last
    assert_equal repo.slug, created_repo.slug
    assert_equal repo_params[:name], created_repo.name
    assert_equal repo_params[:description], created_repo.description
    assert_equal @user.id, created_repo.user_id
    assert_equal repo_params[:privacy], created_repo.privacy

    # with group
    sign_in_user
    repo = build(:repository)
    repo_params = {
      name: repo.name,
      slug: repo.slug,
      description: repo.description,
      user_id: @group.id
    }
    post "/repositories", params: { repository: repo_params }
    assert_equal 403, response.status

    sign_in_role :editor, group: @group
    post "/repositories", params: { repository: repo_params }
    assert_redirected_to "/#{@group.slug}/#{repo.slug}"
  end

  test "GET /:user/:repo" do
    # public repo
    repo = create(:repository, user: @group)

    get "/#{repo.user.slug}/#{repo.slug}"
    assert_equal 200, response.status

    assert_match /#{repo.name}/, response.body
    assert_select ".btn-create-doc", 0
    assert_select ".reponav-item-docs", 1
    assert_select ".repo-toc"
    assert_select ".label-private", 0

    assert_raise(ActiveRecord::RecordNotFound) do
      get "/foo/#{repo.slug}"
    end

    assert_raise(ActiveRecord::RecordNotFound) do
      get "/#{@user.slug}/#{repo.slug}"
    end

    # private repo
    repo = create(:repository, user: @group, privacy: :private)
    get "/#{repo.user.slug}/#{repo.slug}"
    assert_equal 403, response.status

    sign_in_role :editor, group: @group
    get "/#{repo.user.slug}/#{repo.slug}"
    assert_equal 200, response.status
    assert_no_match /#{repo.to_path("/settings")}/, response.body
    assert_select ".btn-create-doc"
    assert_select ".label-private"

    sign_in_role :admin, group: @group
    get "/#{repo.user.slug}/#{repo.slug}"
    assert_equal 200, response.status
    assert_match /#{repo.to_path("/settings")}/, response.body
    assert_select ".btn-create-doc"

    # has_doc? enable, should render :docs
    repo = create(:repository, user: @group)
    repo.update(has_toc: 0)
    get "/#{repo.user.slug}/#{repo.slug}"
    assert_equal 200, response.status
    assert_select ".reponav-item-docs", 0
    assert_select ".repository-docs"
  end

  test "GET /:user/:repo TOC List" do
    repo = create(:repository, user: @group)
    doc0 = create(:doc, repository: repo)
    doc1 = create(:doc, repository: repo)
    get "/#{repo.user.slug}/#{repo.slug}"
    assert_equal 200, response.status
    assert_select ".toc-item", 2
    assert_select ".toc-item a.item-link[href=\"/#{@group.slug}/#{repo.slug}/#{doc0.slug}\"]", 1
    assert_select ".toc-item a.item-link[href=\"/#{@group.slug}/#{repo.slug}/#{doc1.slug}\"]", 1
  end

  test "POST/DELETE /:user/:repo/action" do
    repo = create(:repository)
    repo1 = create(:repository)

    post "/#{repo.user.slug}/#{repo.slug}/action?type=star"
    assert_equal 302, response.status

    sign_in @user
    post "/#{repo.user.slug}/#{repo.slug}/action", params: { action_type: :star, format: :js }
    assert_equal 200, response.status
    assert_match /.repository-#{repo.id}-star-button/, response.body
    assert_match /btn.attr\(\"data-undo-label\"\)/, response.body
    repo.reload
    assert_equal 1, repo.stars_count

    post "/#{repo1.user.slug}/#{repo1.slug}/action", params: { action_type: :star, format: :js }
    repo1.reload
    assert_equal 1, repo1.stars_count

    post "/#{repo.user.slug}/#{repo.slug}/action", params: { action_type: :watch, format: :js }
    assert_equal 200, response.status
    assert_match /.repository-#{repo.id}-watch-button/, response.body
    repo.reload
    assert_equal 1, repo.stars_count
    assert_equal 1, repo.watches_count

    delete "/#{repo.user.slug}/#{repo.slug}/action", params: { action_type: :star, format: :js }
    assert_equal 200, response.status
    assert_match /btn.attr\(\"data-label\"\)/, response.body
    repo.reload
    assert_equal 0, repo.stars_count
  end
end
