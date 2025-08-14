require 'rails_helper'

RSpec.describe Api::V1::UsersController, type: :controller do
  let(:user) { create(:user) }
  let(:admin_user) { create(:user, admin: true) }
  let(:valid_attributes) { { name: 'John Doe', email: 'john@example.com', password: 'password123' } }
  
  before do
    allow(controller).to receive(:current_user).and_return({ user: user })
  end

  describe 'GET #me' do
    it 'returns current user information' do
      get :me
      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['user']['id']).to eq(user.id)
    end
  end

  describe 'GET #show' do
    context 'when user views own profile' do
      it 'returns user information' do
        get :show, params: { id: user.id }
        expect(response).to have_http_status(:ok)
      end
    end

    context 'when user tries to view another user profile' do
      let(:other_user) { create(:user) }
      
      it 'returns forbidden' do
        get :show, params: { id: other_user.id }
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when admin views any user profile' do
      before do
        allow(controller).to receive(:current_user).and_return({ user: admin_user })
      end

      it 'returns user information' do
        get :show, params: { id: user.id }
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe 'POST #create' do
    context 'with valid parameters' do
      it 'creates a new user' do
        expect {
          post :create, params: { user: valid_attributes }
        }.to change(User, :count).by(1)
        
        expect(response).to have_http_status(:created)
      end
    end

    context 'with invalid parameters' do
      it 'does not create a user' do
        expect {
          post :create, params: { user: { email: 'invalid-email' } }
        }.not_to change(User, :count)
        
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'PUT #update' do
    context 'when user updates own profile' do
      it 'updates the user' do
        put :update, params: { id: user.id, user: { name: 'Updated Name' } }
        expect(response).to have_http_status(:ok)
        expect(user.reload.name).to eq('Updated Name')
      end
    end
  end

  describe 'DELETE #destroy' do
    context 'when admin deletes another user' do
      before do
        allow(controller).to receive(:current_user).and_return({ user: admin_user })
      end

      it 'deletes the user' do
        delete :destroy, params: { id: user.id }
        expect(response).to have_http_status(:ok)
        expect(User.exists?(user.id)).to be_false
      end
    end

    context 'when admin tries to delete themselves' do
      before do
        allow(controller).to receive(:current_user).and_return({ user: admin_user })
      end

      it 'returns forbidden' do
        delete :destroy, params: { id: admin_user.id }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
