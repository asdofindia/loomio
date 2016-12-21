require 'rails_helper'

describe API::PollsController do
  let(:group) { create :group }
  let(:another_group) { create :group }
  let(:discussion) { create :discussion, group: group }
  let(:another_discussion) { create :discussion, group: group }
  let(:non_group_discussion) { create :discussion }
  let(:user) { create :user }
  let(:another_user) { create :user }
  let!(:poll) { create :poll, discussion: discussion, author: user, poll_template: poll_template }
  let(:another_poll) { create :poll, discussion: another_discussion }
  let(:non_group_poll) { create :poll }
  let(:poll_template) { PollTemplate.motion_template }
  let(:poll_params) {{
    name: "hello",
    description: "is it me you're looking for?",
    discussion_id: discussion.id,
    poll_template_id: poll_template.id,
    closing_at: 3.days.from_now
  }}

  before { group.add_member! user }

  describe 'show' do
    it 'shows a poll' do
      sign_in user
      get :show, id: poll.key
      json = JSON.parse(response.body)
      expect(json['polls'].length).to eq 1
      expect(json['polls'][0]['key']).to eq poll.key
    end

    it 'does not show a poll you do not have access to' do
      sign_in another_user
      get :show, id: poll.key
      expect(response.status).to eq 403
    end
  end

  describe 'index' do
    it 'shows polls in a discussion' do
      sign_in user
      get :index, discussion_id: discussion.key
      json = JSON.parse(response.body)
      poll_keys = json['polls'].map { |p| p['key'] }
      expect(poll_keys).to include poll.key
      expect(poll_keys).to_not include another_poll.key
      expect(poll_keys).to_not include non_group_poll.key
    end

    it 'does not allow user to see polls theyre not allowed to see' do
      sign_in user
      get :index, discussion_id: non_group_discussion.key
      expect(response.status).to eq 403
    end
  end

  describe 'create' do
    it 'creates a poll' do
      sign_in user
      expect { post :create, poll: poll_params }.to change { Poll.count }.by(1)
      expect(response.status).to eq 200

      poll = Poll.last
      expect(poll.name).to eq poll_params[:name]
      expect(poll.poll_template).to eq poll_template
      expect(poll.discussion).to eq discussion
      expect(poll.author).to eq user

      json = JSON.parse(response.body)
      expect(json['polls'].length).to eq 1
      expect(json['polls'][0]['key']).to eq poll.key
    end

    it 'does not allow visitors to create polls' do
      expect { post :create, poll: poll_params }.to_not change { Poll.count }
      expect(response.status).to eq 403
    end

    it 'does not allow non-members to create polls' do
      sign_in another_user
      expect { post :create, poll: poll_params }.to_not change { Poll.count }
      expect(response.status).to eq 403
    end
  end

  describe 'update' do
    it 'updates a poll' do
      sign_in user
      post :update, id: poll.key, poll: poll_params
      expect(poll.reload.name).to eq poll_params[:name]
      expect(poll.description).to eq poll_params[:description]
      expect(poll.closing_at).to be_within(1.second).of(poll_params[:closing_at])

      expect(response.status).to eq 200
      json = JSON.parse(response.body)
      expect(json['polls'].length).to eq 1
      expect(json['polls'][0]['key']).to eq poll.key
    end

    it 'cannot move a poll between discussions' do
      post :update, id: poll.key, poll: { discussion_id: another_discussion.id }
      expect(poll.reload.discussion).to eq discussion
    end

    it 'does not allow visitors to update polls' do
      post :update, id: poll.key, poll: poll_params
      expect(response.status).to eq 403
    end

    it 'does not allow members other than the author to update polls' do
      sign_in another_user
      post :update, id: poll.key, poll: poll_params
      expect(response.status).to eq 403
    end
  end

  describe 'close' do
    it 'closes a poll' do
      sign_in user
      post :close, id: poll.key
      expect(response.status).to eq 200
      expect(poll.reload.open?).to eq false
    end

    it 'does not close an already closed poll' do
      sign_in user
      poll.update(closed_at: 1.day.ago)
      post :close, id: poll.key
      expect(response.status).to eq 403
    end

    it 'does not allow visitors to close polls' do
      post :close, id: poll.key
      expect(response.status).to eq 403
      expect(poll.reload.open?).to eq true
    end

    it 'does not allow members other than the author to close polls' do
      sign_in another_user
      post :close, id: poll.key
      expect(response.status).to eq 403
      expect(poll.reload.open?).to eq true
    end
  end
end
