module Api
  module V1
    class MembershipsController < BaseController
      before_action :require_admin!, only: %i[create update destroy]
      before_action :set_membership, only: %i[show update destroy]

      def index
        memberships = MembershipRecord.all.order(created_at: :desc)
        result = paginate(memberships)
        render_success(
          result[:data].map { |m| serialize_membership(m) },
          meta: result[:meta]
        )
      end

      def show
        render_success(serialize_membership(@membership))
      end

      def create
        membership = MembershipRecord.new(membership_create_params)
        if membership.save
          render_created(serialize_membership(membership))
        else
          raise Domain::Shared::Errors::ValidationError.new(
            "Membership creation failed",
            details: membership.errors.full_messages
          )
        end
      end

      def update
        if @membership.update(membership_update_params)
          render_success(serialize_membership(@membership))
        else
          raise Domain::Shared::Errors::ValidationError.new(
            "Membership update failed",
            details: @membership.errors.full_messages
          )
        end
      end

      def destroy
        @membership.destroy!
        head :no_content
      end

      private

      def set_membership
        @membership = MembershipRecord.find_by!(id: params[:id])
      rescue ActiveRecord::RecordNotFound
        raise Domain::Shared::Errors::NotFoundError.new("Membership", params[:id])
      end

      def membership_create_params
        params.require(:membership).permit(:user_id, :role, :invited_by)
      end

      def membership_update_params
        params.require(:membership).permit(:role)
      end

      def serialize_membership(membership)
        {
          id: membership.id,
          user_id: membership.user_id,
          role: membership.role,
          invited_by: membership.invited_by,
          created_at: membership.created_at&.iso8601,
          updated_at: membership.updated_at&.iso8601
        }
      end
    end
  end
end
