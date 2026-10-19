// The order and selection of a window's tabs, kept separate from the native views so the rules
// can be tested on their own.

export class TabList {
  /** @type {string[]} tab ids, in display order */
  ids = [];
  /** @type {string | null} */
  selectedId = null;

  get count() {
    return this.ids.length;
  }

  get selectedIndex() {
    return this.selectedId === null ? -1 : this.ids.indexOf(this.selectedId);
  }

  /**
   * Adds a tab. Link-opened tabs go right after their opener; others go at the end.
   * The first tab is always selected.
   */
  add(id, { after = null, activate = true } = {}) {
    const afterIndex = after === null ? -1 : this.ids.indexOf(after);
    const index = afterIndex >= 0 ? afterIndex + 1 : this.ids.length;
    this.ids.splice(index, 0, id);
    if (activate || this.selectedId === null) this.selectedId = id;
    return index;
  }

  /**
   * Removes a tab. If it was selected, the tab that slides into its place (or the new last tab)
   * becomes selected, as in browsers.
   * @returns {boolean} false if the id wasn't present
   */
  remove(id) {
    const index = this.ids.indexOf(id);
    if (index < 0) return false;
    this.ids.splice(index, 1);
    if (this.selectedId === id) this.selectedId = this.ids[Math.min(index, this.ids.length - 1)] ?? null;
    return true;
  }

  select(id) {
    if (this.ids.includes(id)) this.selectedId = id;
  }

  /** Next (+1) / previous (-1) tab, wrapping around. */
  selectOffset(offset) {
    if (this.ids.length < 2) return;
    const index = (((this.selectedIndex + offset) % this.ids.length) + this.ids.length) % this.ids.length;
    this.selectedId = this.ids[index];
  }

  /** 1–8 select that tab, 9 selects the last one (as in browsers). */
  selectNumber(number) {
    const index = number === 9 ? this.ids.length - 1 : number - 1;
    if (index >= 0 && index < this.ids.length) this.selectedId = this.ids[index];
  }

  /** Moves the tab at `from` to `to` (after a drag in the tab bar). */
  move(from, to) {
    if (from === to || from < 0 || to < 0 || from >= this.ids.length || to >= this.ids.length) return;
    const [id] = this.ids.splice(from, 1);
    this.ids.splice(to, 0, id);
  }
}
