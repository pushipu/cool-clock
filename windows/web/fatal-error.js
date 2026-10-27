// A terminal renderer failure must invalidate native health even after `ready`.
export function createFatalErrorHandler({ stop, display, post }) {
  let failed = false;
  return {
    get failed() { return failed; },
    fail(message) {
      if (failed) return;
      failed = true;
      stop();
      display(String(message));
      post('error');
    },
  };
}
