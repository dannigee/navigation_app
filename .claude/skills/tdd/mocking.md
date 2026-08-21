# Mocking

**Load this when:** about to add any mock, partial mock, or test double.

**Core principle:** mocks are tools to isolate, not things to test. Test what the real code does, not what the mocks do.

## Where to mock

**Mock at system boundaries only:**

- External APIs (payment gateways, third-party services)
- Real network calls you don't own
- Databases (sometimes — prefer a real test DB when feasible)
- Time, randomness, UUIDs
- File system (sometimes)

**Never mock:**

- Your own classes or modules
- Internal collaborators
- Pure logic you control
- Anything you could pass a real instance of

If you can't write the test without mocking an internal collaborator, the interface is coupled wrong. Fix the interface (see `interface-design.md`), don't paper over it with mocks.

## Designing for mockability

At system boundaries, design interfaces that are easy to mock.

### 1. Dependency injection

Pass external dependencies in rather than creating them internally:

```typescript
// Easy to mock
function processPayment(order, paymentClient) {
  return paymentClient.charge(order.total);
}

// Hard to mock
function processPayment(order) {
  const client = new StripeClient(process.env.STRIPE_KEY);
  return client.charge(order.total);
}
```

### 2. SDK-style over generic fetchers

Create specific functions for each external operation instead of one generic function with conditional logic:

```typescript
// GOOD: each function is independently mockable
const api = {
  getUser: (id) => fetch(`/users/${id}`),
  getOrders: (userId) => fetch(`/users/${userId}/orders`),
  createOrder: (data) => fetch('/orders', { method: 'POST', body: data }),
};

// BAD: mocking requires conditional logic inside the mock
const api = {
  fetch: (endpoint, options) => fetch(endpoint, options),
};
```

The SDK approach means:
- Each mock returns one specific shape
- No conditional logic in test setup
- Easy to see which endpoints a test exercises
- Type safety per endpoint

## Anti-patterns

### Anti-pattern 1: Testing mock behavior

```typescript
// BAD: testing that the mock exists
test('renders sidebar', () => {
  render(<Page />);
  expect(screen.getByTestId('sidebar-mock')).toBeInTheDocument();
});
```

You're verifying the mock works, not that the component works. The test passes when the mock is present and fails when it isn't — it tells you nothing about real behavior.

**Fix:** don't assert on mock elements. Test real component behavior, or if the component must be mocked for isolation, assert on the surrounding behavior (not on the mock itself).

**Gate:** before asserting on any mock element, ask: *am I testing real behavior or just mock existence?* If the latter, delete the assertion.

### Anti-pattern 2: Testing through call counts when you could test through results

```typescript
// BAD: asserts interaction, not behavior
test('checkout calls paymentService.process', async () => {
  const mockPayment = jest.mock(paymentService);
  await checkout(cart, payment);
  expect(mockPayment.process).toHaveBeenCalledWith(cart.total);
});

// GOOD: asserts the user-visible outcome
test('user can checkout with valid cart', async () => {
  const result = await checkout(cart, paymentMethod);
  expect(result.status).toBe('confirmed');
});
```

Call-count assertions couple the test to the *implementation path*. Result assertions couple the test to *behavior*. Behavior-level assertions survive refactors; call-count assertions don't.

**When call counts are legitimate:** when the behavior claim is specifically about *interaction* — "we never call stripe if validation fails", "we call the logger exactly once." Those are interaction contracts, not implementation details. Assert on them only when the interaction IS the behavior.

### Anti-pattern 3: Test-only methods in production classes

```typescript
// BAD: destroy() only used in tests
class Session {
  async destroy() {
    await this._workspaceManager?.destroyWorkspace(this.id);
  }
}

afterEach(() => session.destroy());
```

Production class polluted with test-only code. Dangerous if accidentally called in production. Violates YAGNI.

**Fix:** put cleanup in test utilities, not in the production class.

```typescript
// test-utils/
export async function cleanupSession(session: Session) {
  const workspace = session.getWorkspaceInfo();
  if (workspace) {
    await workspaceManager.destroyWorkspace(workspace.id);
  }
}

afterEach(() => cleanupSession(session));
```

**Gate:** before adding any method to a production class, ask: *is this only used by tests?* If yes, put it in test utilities instead.

### Anti-pattern 4: Mocking without understanding side effects

```typescript
// BAD: mock breaks the thing the test depends on
test('detects duplicate server', () => {
  vi.mock('ToolCatalog', () => ({
    discoverAndCacheTools: vi.fn().mockResolvedValue(undefined)
  }));

  await addServer(config);
  await addServer(config);  // Should throw duplicate — but won't, because the mock skipped the config write
});
```

Over-mocking to "be safe" strips out side effects the test depended on. The test then passes for the wrong reason or fails mysteriously.

**Fix:** mock at the correct level. Mock the slow external piece, preserve the behavior the test needs.

**Gate:** before mocking any method, ask:
1. What side effects does the real method have?
2. Does this test depend on any of those side effects?
3. Do I fully understand what this test needs?

If unsure, run the test with the real implementation first, observe what it actually needs, then add minimal mocking at the right level.

### Anti-pattern 5: Incomplete mocks

```typescript
// BAD: partial mock — only fields you think you need
const mockResponse = {
  status: 'success',
  data: { userId: '123', name: 'Alice' }
  // Missing: metadata that downstream code uses
};

// Later: breaks when code accesses response.metadata.requestId
```

Partial mocks hide structural assumptions. Downstream code may depend on fields you didn't include, and the test passes while integration fails.

**Iron rule:** mock the COMPLETE data structure as it exists in reality, not just the fields your immediate test uses.

```typescript
// GOOD: mirrors the real API
const mockResponse = {
  status: 'success',
  data: { userId: '123', name: 'Alice' },
  metadata: { requestId: 'req-789', timestamp: 1234567890 }
};
```

**Gate:** before creating a mock response, check the real API response shape. Include every field the system might consume downstream. If uncertain, include all documented fields.

### Anti-pattern 6: Verifying through the database instead of the interface

```typescript
// BAD: bypasses the interface to verify
test('createUser saves to database', async () => {
  await createUser({ name: 'Alice' });
  const row = await db.query("SELECT * FROM users WHERE name = ?", ['Alice']);
  expect(row).toBeDefined();
});

// GOOD: verifies through the interface
test('createUser makes user retrievable', async () => {
  const user = await createUser({ name: 'Alice' });
  const retrieved = await getUser(user.id);
  expect(retrieved.name).toBe('Alice');
});
```

Reaching into the database couples the test to the storage implementation. When you swap Postgres for something else, or rename a column, the test breaks without the behavior changing. Verify through the interface the caller would use.

## When mocks become too complex

**Warning signs:**
- Mock setup longer than the test logic
- Mocking everything to make the test pass
- Mocks missing methods the real components have
- Test breaks when the mock changes, not when behavior changes

Ask: *do we need to be using a mock here?* Integration tests with real components are often simpler than complex mocks.

## Quick reference

| Anti-pattern | Fix |
|---|---|
| Assert on mock elements | Test real component or unmock it |
| Call-count assertions for behavior | Assert on the returned result |
| Test-only methods in production | Move to test utilities |
| Mock without understanding side effects | Understand dependencies first, mock minimally |
| Incomplete mocks | Mirror the real API completely |
| Verify through the database | Verify through the public interface |
| Over-complex mocks | Consider integration tests instead |

## Red flags

- Assertion checks for `*-mock` test IDs
- Methods only called in test files
- Mock setup is >50% of the test
- Test fails when you remove the mock
- Can't explain why the mock is needed
- Mocking "just to be safe"

## The bottom line

**Mocks are tools to isolate, not things to test.** If you find yourself testing mock behavior, you've gone wrong. Test real behavior, or question why you're mocking at all.
