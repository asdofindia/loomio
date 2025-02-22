<script lang="coffee">
import GroupService from '@/shared/services/group_service'
import Records        from '@/shared/services/records'
import Session from '@/shared/services/session'
import EventBus from '@/shared/services/event_bus'
import AppConfig      from '@/shared/services/app_config'
import RecipientsAutocomplete from '@/components/common/recipients_autocomplete'
import AbilityService from '@/shared/services/ability_service'
import Flash   from '@/shared/services/flash'
import { uniq, debounce } from 'lodash'

export default
  components:
    RecipientsAutocomplete: RecipientsAutocomplete

  props:
    group: Object

  data: ->
    query: ''
    recipients: []
    reset: false
    saving: false
    groupIds: [@group.id]
    excludedUserIds: []
    message: ''
    subscription: {}
    cannotInvite: false
    upgradeUrl: AppConfig.baseUrl + 'upgrade'

  mounted: ->
    @updateSuggestions()
    @watchRecords
      collections: ['memberships']
      query: (records) => @updateSuggestions()

    @subscription = @group.parentOrSelf().subscription
    @cannotInvite = !@subscription.active || (@subscription.max_members && @invitationsRemaining < 1)

  methods:
    fetchMemberships: debounce ->
      @loading = true
      Records.memberships.fetch
        params:
          exclude_types: 'group'
          q: @query
          group_id: @group.id
          per: 20
      .finally =>
        @loading = false
    , 300

    inviteRecipients: ->
      @saving = true
      Records.remote.post 'announcements',
        group_id: @group.id
        invited_group_ids: @groupIds
        recipient_emails: @recipients.filter((r) -> r.type == 'email').map((r) -> r.id)
        recipient_user_ids: @recipients.filter((r) -> r.type == 'user').map((r) -> r.id)
        recipient_message: @message

      .then (data) =>
        Flash.success('announcement.flash.success', { count: data.memberships.length })
        EventBus.$emit('closeModal')
      .finally =>
        @saving = false

    newQuery: (query) ->
      @query = query
      @fetchMemberships()
      @updateSuggestions()

    newRecipients: (recipients) -> @recipients = recipients

    updateSuggestions: ->
      @excludedUserIds = @group.memberIds()

    # findUsers: ->
    #   userIdsInGroup = Records.memberships.collection.
    #     chain().find(groupId: @group.id).
    #     data().map (m) -> m.userId
    #   membershipsChain = Records.memberships.collection.chain()
    #   membershipsChain = membershipsChain.find(groupId: { $in: @group.parentOrSelf().organisationIds() })
    #   membershipsChain = membershipsChain.find(userId: { $nin: userIdsInGroup })
    #
    #   userIdsNotInGroup = uniq membershipsChain.data().map((m) -> m.userId)
    #
    #   chain = Records.users.collection.chain()
    #   chain = chain.find(id: {$in: userIdsNotInGroup})
    #
    #
    #   if @query
    #     chain = chain.find
    #       $or: [
    #         {name: {'$regex': ["^#{@query}", "i"]}}
    #         {username: {'$regex': ["^#{@query}", "i"]}}
    #         {name: {'$regex': [" #{@query}", "i"]}}
    #       ]
    #   chain.data()

  computed:
    invitableGroups: ->
      @group.parentOrSelf().selfAndSubgroups().filter (g) -> AbilityService.canAddMembersToGroup(g)
    tooManyInvitations: ->
      @subscription.max_members && (@invitationsRemaining < 0)
    invitationsRemaining: ->
      (@subscription.max_members || 0) - @group.parentOrSelf().orgMembershipsCount - @recipients.length


</script>
<template lang="pug">
.group-invitation-form
  .px-4.pt-4
    .d-flex.justify-space-between
      h1.headline(tabindex="-1" v-t="{path: 'announcement.send_group', args: {name: group.name} }")
      dismiss-modal-button

    div.py-4(v-if="cannotInvite")
      .announcement-form__invite
        p(v-if="invitationsRemaining < 1" v-html="$t('announcement.form.no_invitations_remaining', {upgradeUrl: upgradeUrl, maxMembers: subscription.max_members})")
        p(v-if="!subscription.active" v-html="$t('discussion.subscription_canceled', {upgradeUrl: upgradeUrl})")
    div(v-else)
      recipients-autocomplete(
        :label="$t('announcement.form.who_to_invite')"
        :placeholder="$t('announcement.form.placeholder')"
        :excluded-user-ids="excludedUserIds"
        :reset="reset"
        :model="group"
        @new-query="newQuery"
        @new-recipients="newRecipients")
      div(v-if="subscription.max_members")
        p.caption(v-if="!tooManyInvitations" v-html="$t('announcement.form.invitations_remaining', {count: invitationsRemaining, upgradeUrl: upgradeUrl })")
        p.caption(v-if="tooManyInvitations" v-html="$t('announcement.form.too_many_invitations', {upgradeUrl: upgradeUrl})")
      div.mb-4(v-if="invitableGroups.length > 1")
        label.lmo-label(v-t="'announcement.select_groups'")
        //- v-label Select groups
        div(v-for="group in invitableGroups" :key="group.id")
          v-checkbox.invitation-form__select-groups(:class="{'ml-4': !group.isParent()}" v-model="groupIds" :label="group.name" :value="group.id" hide-details)

      v-textarea(rows="3" v-model="message" :label="$t('announcement.form.invitation_message_label')" :placeholder="$t('announcement.form.invitation_message_placeholder')")

      v-card-actions
        help-link(path="en/user_manual/groups/membership" text="invitation_form.help_inviting_people")
        v-spacer
        v-btn.announcement-form__submit(color="primary" :disabled="!recipients.length || tooManyInvitations || groupIds.length == 0" @click="inviteRecipients" :loading="saving")
          span(v-t="'common.action.invite'")

</template>
<style lang="css">

.lmo-label {
  color: rgba(0, 0, 0, 0.6);
  height: 20px;
  line-height: 20px;
  max-width: 133%;
  transform: translateY(-18px) scale(0.75);
  max-width: 90%;
  overflow: hidden;
  text-overflow: ellipsis;
  top: 6px;
  white-space: nowrap;
  pointer-events: none;
  font-size: 12px;
  line-height: 1;
  min-height: 8px;
  transition: 0.3s cubic-bezier(0.25, 0.8, 0.5, 1);
}

.invitation-form__select-groups {
  margin-top: 8px;
}

</style>
