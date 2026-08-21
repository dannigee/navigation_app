# Good and Bad Tests

**Load this when:** writing a test and unsure if it's well-shaped, or reviewing tests that feel brittle.

## Good tests

**Integration-style:** test through real interfaces, not mocks of internal parts.

```typescript
// GOOD: tests observable behavior through the public interface
test('user can checkout with valid cart', async () => {
  const cart = createCart();
  cart.add(product);
  const result = await checkout(cart, paymentMethod);
  expect(result.status).toBe('confirmed');
});
```

Characteristics:

- Tests behavior a user or caller cares about
- Uses public API only
- Survives internal refactors
- Describes WHAT, not HOW
- One logical assertion per test
- Reads like a specification: "user can checkout with valid cart" tells you exactly what capability exists

```typescript
// GOOD: verifies through the interface
test('createUser makes user retrievable', async () => {
  const user = await createUser({ name: 'Alice' });
  const retrieved = await getUser(user.id);
  expect(retrieved.name).toBe('Alice');
});
```

```typescript
// GOOD: tests real behavior, no mocks
test('retries failed operations 3 times', async () => {
  let attempts = 0;
  const operation = () => {
    attempts++;
    if (attempts < 3) throw new Error('fail');
    return 'success';
  };

  const result = await retryOperation(operation);

  expect(result).toBe('success');
  expect(attempts).toBe(3);
});
```

Clear name. Real counter, not a mock. One thing tested. You can tell what the function is supposed to do just by reading it.

## Bad tests

**Implementation-detail tests:** coupled to internal structure.

```typescript
// BAD: tests implementation details
test('checkout calls paymentService.process', async () => {
  const mockPayment = jest.mock(paymentService);
  await checkout(cart, payment);
  expect(mockPayment.process).toHaveBeenCalledWith(cart.total);
});
```

Red flags:

- Mocking internal collaborators
- Testing private methods
- Asserting on call counts or call order when the behavior claim isn't about interaction
- Test breaks when refactoring without any behavior change
- Test name describes HOW, not WHAT
- Verifying through external means instead of the interface

```typescript
// BAD: bypasses the interface
test('createUser saves to database', async () => {
  await createUser({ name: 'Alice' });
  const row = await db.query("SELECT * FROM users WHERE name = ?", ['Alice']);
  expect(row).toBeDefined();
});
```

Couples the test to the storage layer. Change the database schema, break the test without changing any observable behavior.

```typescript
// BAD: vague name, tests the mock
test('retry works', async () => {
  const mock = jest.fn()
    .mockRejectedValueOnce(new Error())
    .mockRejectedValueOnce(new Error())
    .mockResolvedValueOnce('success');
  await retryOperation(mock);
  expect(mock).toHaveBeenCalledTimes(3);
});
```

What does "retry works" mean? Who knows. And the assertion is about the mock, not about the function's behavior. Compare to the good version above — the good version would catch a bug where the function never returned the success value. This one wouldn't.

## The heuristic

**Would this test survive a refactor that preserved behavior?**

If yes, it's a good test. If no, it's coupled to implementation and will rot. When in doubt, rename every internal function in the module and see which tests break. The ones that break were testing HOW, not WHAT.

## One logical assertion per test

If your test name contains "and" — `test('validates email and rejects empty names and trims whitespace')` — split it. Each behavior gets its own test. That way:

- When one fails, the name tells you exactly which behavior broke
- You can evolve each behavior independently
- Test names become executable documentation of the system's capabilities

Multiple `expect()` calls are fine if they all describe the same logical assertion (e.g., `expect(result.status).toBe('confirmed')` and `expect(result.id).toBeDefined()` are both saying "the checkout succeeded"). Multiple unrelated assertions in one test are a smell.
