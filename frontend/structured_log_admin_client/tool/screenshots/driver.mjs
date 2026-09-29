/// Driving this application from a browser, for anything that needs to.
///
/// Extracted from `shoot.mjs` when a second harness needed the same three
/// hard-won pieces of knowledge (`browser-e2e/`). Nothing here imports
/// puppeteer: every function takes a `page` and works against whatever
/// handed it one, which is also why this file can be imported from a
/// directory with its own `node_modules` and no shared install.
///
/** The application's own semantics tree, as the browser exposes it.
 *
 * Flutter labels a control two different ways depending on what it is: an
 * `aria-label` on some, the text itself as the element's content on others
 * (a button reads `<flt-semantics role="button">Sign in</flt-semantics>`).
 * Matching reads whichever is there, which is why nothing below has to know
 * which kind a given control happens to be.
 */
const MATCH = `(node) => (node.getAttribute('aria-label') || node.textContent || '').trim()`;

const driver = (page) => ({
  async click(label, options = {}) {
    const handle = await find(page, label, options);
    await handle.click();
    await settle(page);
  },

  /// Types into the field that belongs to the visible label [label].
  ///
  /// Not `find(label)` then click: the input carries **no accessible name**
  /// of its own — `AdminTextField` draws the label as a separate line of
  /// text above it — so the label matches a caption, and clicking a caption
  /// focuses nothing. What the tree does give is order: a field's own node
  /// is the next one after its label, and it is the one holding an `input`.
  ///
  /// (That the inputs are nameless is worth fixing in the widget rather than
  /// worked around here — a screen reader announces nothing for them either.
  /// Until then, this is the honest way to reach them.)
  async type(label, text, options = {}) {
    const handle = await find(page, label, options);
    const input = await handle.evaluateHandle((node) => {
      const all = [...document.querySelectorAll('flt-semantics')];
      for (let i = all.indexOf(node); i < all.length; i++) {
        const field = all[i].querySelector('input, textarea');
        if (field) return field;
      }
      return null;
    });
    const element = input.asElement();
    if (!element) throw new Error(`no field under "${label}"`);
    // Set the value and announce it, which is how a screen reader enters
    // text and the only way that works here. Synthetic key events do not:
    // with semantics on, Flutter routes typing through this element rather
    // than a hidden one of its own, and DOM focus goes straight back to
    // `<flutter-view>` — so `keyboard.type` lands nowhere. Measured, not
    // assumed: a click on the field shows the framework's focus ring while
    // both the element's value and the rendered text stay empty.
    // Focus first, with a real pointer event at the field's own box: the
    // framework only takes text from the element it considers active, so
    // setting a second field without focusing it silently changes nothing —
    // which is how a sign-in with the right password still failed.
    const box = await element.boundingBox();
    if (box) {
      await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
      await settle(page, 1);
    }
    await element.evaluate((node, value) => {
      node.value = value;
      node.dispatchEvent(new Event('input', { bubbles: true }));
    }, text);
    await settle(page);
  },

  /// Delivers [count] entries into the open live subscription, through the
  /// hook `guide_app.dart` installs. The only thing in this file that asks
  /// the application to do something no reader could do by clicking.
  async deliver(count) {
    await page.evaluate((howMany) => window.guideDeliverEntries(howMany), count);
    await settle(page, 5);
  },

  async press(key) {
    await page.keyboard.press(key);
    await settle(page);
  },

  async waitFor(label, options = {}) {
    await find(page, label, options);
  },

  /** Every label the tree currently carries — for writing a new scene. */
  async labels() {
    return page.evaluate(
      (matcher) =>
        [...document.querySelectorAll('flt-semantics')]
          .filter((node) => !node.querySelector('flt-semantics'))
          .map(eval(matcher))
          .filter((text) => text.length > 0),
      MATCH,
    );
  },
});

/// Waits for a control whose label contains [label] and answers its handle.
///
/// `exact` for the times a short name is a substring of a longer one, `nth`
/// for a list where the same label repeats, `role` for a button that sits
/// inside a row carrying the same words.
async function find(page, label, { exact = false, nth = 0, role } = {}) {
  const criteria = { label, exact, nth, role: role ?? null };
  await page.waitForFunction(
    (matcher, want) =>
      [...document.querySelectorAll('flt-semantics')].filter((node) => {
        if (node.querySelector('flt-semantics')) return false;
        if (want.role && node.getAttribute('role') !== want.role) return false;
        const own = eval(matcher)(node);
        return want.exact ? own === want.label : own.includes(want.label);
      }).length > want.nth,
    { timeout: 20000 },
    MATCH,
    criteria,
  );
  const handles = await page.$$('flt-semantics');
  const matching = [];
  for (const handle of handles) {
    const keep = await handle.evaluate(
      (node, matcher, want) => {
        // A parent in this tree carries all of its children's text, so a
        // match on an ancestor would click the middle of the screen.
        if (node.querySelector('flt-semantics')) return false;
        if (want.role && node.getAttribute('role') !== want.role) return false;
        const own = eval(matcher)(node);
        return want.exact ? own === want.label : own.includes(want.label);
      },
      MATCH,
      criteria,
    );
    if (keep) matching.push(handle);
  }
  if (matching.length <= nth) throw new Error(`no control labelled "${label}"`);
  return matching[nth];
}

/** Lets the frame after an interaction paint before anything is measured. */
async function settle(page, frames = 3) {
  for (let i = 0; i < frames; i++) {
    await page.evaluate(() => new Promise(requestAnimationFrame));
  }
  await new Promise((done) => setTimeout(done, 150));
}

export { MATCH, driver, find, settle };
