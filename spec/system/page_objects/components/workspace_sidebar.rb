# frozen_string_literal: true

module PageObjects
  module Components
    class WorkspaceSidebar < PageObjects::Components::Base
      def toggle
        find(".workspace-team-sidebar .sidebar-section-header-collapsable").click
        self
      end

      def has_expanded_section?
        page.has_css?(".workspace-team-sidebar .sidebar-section-header[aria-expanded='true']")
      end

      def has_collapsed_section?
        page.has_css?(".workspace-team-sidebar .sidebar-section-header[aria-expanded='false']")
      end

      def has_channel?(name)
        page.has_css?(".workspace-team-sidebar__main-link", text: name)
      end

      def has_no_channel?(name)
        page.has_no_css?(".workspace-team-sidebar__main-link", text: name)
      end
    end
  end
end
