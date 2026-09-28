// What each screenshot in `docs/guides/user-guide.md` shows, in the order the
// guide tells it. One scene is one page load: `guide_fixture.dart` decides the
// world, the query decides who is looking at it, and `play` walks to the
// moment the caption describes.
//
// Controls are named by their visible text, which keeps this file readable
// beside the guide and makes a renamed button fail the run loudly instead of
// photographing the wrong screen.

export const scenes = [
  {
    name: 'signing in with a temporary password',
    query: '?stage=onboarding',
    async play(ui, shot) {
      await ui.waitFor('Sign in');
      await shot('01-sign-in-form');

      await ui.type('Username', 'bob');
      await ui.type('Password', 'temporary-password');
      await ui.click('Sign in', { role: 'button' });

      await ui.waitFor('Change your password');
      await ui.type('Current (temporary) password', 'temporary-password');
      await ui.type('New password', 'operator-password');
      await ui.type('Repeat new password', 'operator-password');
      await shot('02-forced-password-change');

      await ui.click('Change password and continue', { role: 'button' });
      await ui.waitFor('Password changed');
      await shot('03-password-changed');
    },
  },
  {
    name: 'what a plain user sees',
    query: '?as=user',
    async play(ui, shot) {
      await ui.waitFor('Groups');
      await shot('04-user-nav-groups');
    },
  },
  {
    name: 'the dashboard',
    async play(ui, shot) {
      await ui.waitFor('Dashboard');
      await shot('20-dashboard');
    },
  },
  {
    name: 'reading logs',
    async play(ui, shot) {
      await ui.click('Log search');
      await ui.waitFor('Logs');
      await shot('05-log-search-scope');

      await ui.click('checkout');
      await ui.waitFor('payment_failed');
      await shot('06-log-browser-feed');

      await ui.click('payment_failed');
      await ui.waitFor('order_id');
      await shot('07-log-entry-detail');

      await ui.press('Escape');
      // The control shows the level in force, not the word "level", so it
      // is named by what it currently says. Opening it and picking an item
      // are two waits, not one: the menu is a popup that has to be in the
      // tree before the item can be clicked, and clicking too early lands
      // on whatever occupied that spot.
      await ui.click('Any level');
      for (let i = 0; i < 5; i++) await ui.press('ArrowDown');
      await ui.press('Enter');
      await ui.click('Search', { role: 'button' });
      await ui.waitFor('payment_failed');
      await shot('08-log-browser-filtered');

      // The badge counts what arrived while the reader was away from the
      // live edge, so something has to arrive: `guide_app.dart` exposes a
      // hook for exactly this picture.
      await ui.deliver(2);
      await ui.waitFor('new entries');
      await shot('09-log-browser-new-badge');
    },
  },
  {
    name: 'groups, projects and keys',
    async play(ui, shot) {
      await ui.click('Groups');
      await ui.waitFor('payments');
      await shot('11-groups-list-owner');

      await ui.click('payments');
      await ui.waitFor('checkout');
      await shot('12-group-detail');

      // Teams first, while this screen is the one on display: everything
      // below opens a project and never comes back, and walking back up the
      // breadcrumb is ambiguous — "payments" also names the group line on
      // the project screen.
      await ui.click('Team', { exact: true });
      await ui.waitFor('New team');
      await shot('17-create-team-dialog');
      await ui.press('Escape');

      await ui.click('Members');
      await ui.waitFor('Members of team');
      await shot('18-team-members-dialog');
      await ui.press('Escape');

      await ui.click('Project', { exact: true });
      await ui.waitFor('New project');
      await shot('13-create-project-dialog');

      await ui.type('Project name', 'shipping');
      await ui.click('Create project', { role: 'button' });
      await ui.waitFor('shipping');
      await ui.click('shipping');
      await ui.waitFor('Project secret keys');
      await shot('14-project-detail');

      await ui.click('Create key', { role: 'button' });
      await ui.waitFor('New secret key');
      await ui.type('Label', 'checkout-prod');
      await ui.click('Create key', { role: 'button' });
      await ui.waitFor('Key created');
      await shot('15-secret-key-reveal');
      await ui.click('I have saved the key — close', { role: 'button' });

      await ui.click('Grant access');
      await ui.waitFor('Recipient');
      await shot('16-grant-access-dialog');
    },
  },
  {
    name: 'the users list',
    async play(ui, shot) {
      await ui.click('Users');
      await ui.waitFor('alice');
      await shot('21-users-list');

      await ui.click('Create user', { role: 'button' });
      await ui.waitFor('New user');
      await ui.type('Username', 'dave');
      await ui.type('Display name', 'Dave Okafor');
      await shot('22-create-user-dialog');
      await ui.press('Escape');

      await ui.click('alice');
      await ui.waitFor('Roles');
      await shot('23-user-detail');

      await ui.click('Edit');
      await ui.waitFor('Edit account');
      await shot('24-edit-user');
      await ui.press('Escape');
    },
  },
  {
    name: 'the refusal to delete a group\'s only owner',
    async play(ui, shot) {
      await ui.click('Users');
      await ui.waitFor('carol');
      await ui.click('carol');
      await ui.waitFor('Delete');
      await ui.click('Delete');
      // The confirmation comes first; the refusal only arrives after it is
      // accepted, which is the point of the picture.
      await ui.waitFor('Delete "carol"?');
      await ui.click('Delete', { role: 'button' });
      await ui.waitFor('sole owner');
      await shot('26-sole-owner-conflict');
    },
  },
  {
    name: 'the audit log',
    async play(ui, shot) {
      await ui.click('Audit');
      await ui.waitFor('Audit');
      await shot('25-audit-log');
    },
  },
  {
    name: 'account settings',
    async play(ui, shot) {
      await ui.click('bob');
      await ui.click('Account settings');
      await ui.waitFor('Language');
      await shot('10-account-settings');

      // "Change password" names both the section and its button; the
      // heading is what a plain match finds first.
      await ui.click('Change password', { role: 'button' });
      await ui.waitFor('Keep other devices signed in');
      await shot('10a-change-password-form');
    },
  },
];
