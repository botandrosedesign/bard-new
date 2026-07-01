@new
Feature: bard new
  Create a new bard-managed Rails project end-to-end: a real GitHub repo,
  a passing GitHub Actions CI run, and a live deploy on staging. Requires
  BARD_E2E=1 and SSH credentials (see features/support/new_server.rb);
  otherwise the scenario is skipped.

  Background:
    Given a bard new server is running

  Scenario: creates, verifies, and tears down a new Rails project
    When I run bard new for real
    Then the output should contain "created!"
    And the project isolates parallel test databases
    And the project has its own rvm gemset
    And the project is served by Passenger at its dev url
    And the project's CI suite passed on GitHub Actions
    And the project responds on staging
    When I destroy the project
    Then the local rvm gemset is removed
    And the staging deploy is removed
    And the GitHub repo no longer exists
