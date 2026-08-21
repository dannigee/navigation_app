# Interface Design for Testability

**Load this when:** the test feels awkward to write, you're reaching for mocks to isolate internal collaborators, or test setup is ballooning.

The heuristic: **if the test is hard to write, the interface is wrong, not the test.**

Good interfaces make testing natural. Three rules:

## 1. Accept dependencies, don't create them

```typescript
// Testable — collaborator comes in through the constructor or call site
function processOrder(order, paymentGateway) {
  return paymentGateway.charge(order.total);
}

// Hard to test — collaborator is created inside, hidden from the test
function processOrder(order) {
  const gateway = new StripeGateway();
  return gateway.charge(order.total);
}
```

When a function constructs its own external collaborators, you can't substitute a fake at a system boundary without patching globals or monkey-patching the module. That's a smell that the interface is wrong.

## 2. Return results, don't produce side effects

```typescript
// Testable — assert on the returned value
function calculateDiscount(cart): Discount {
  return { amount: cart.total * 0.1 };
}

// Hard to test — you have to reach into the cart afterwards to verify
function applyDiscount(cart): void {
  cart.total -= cart.total * 0.1;
}
```

Pure functions that return values are trivially testable. Functions that mutate hidden state force the test to know how and where the mutation happened, coupling the test to implementation.

When you must produce side effects (writing to a database, calling an API), push them to the outer edges and keep the core logic pure. The pure core is what gets thoroughly tested.

## 3. Small surface area

- Fewer methods = fewer tests needed
- Fewer parameters = simpler test setup
- Fewer options = fewer combinations to verify

If a class has twelve public methods, you have twelve test surfaces. If it has three, you have three. Pair this with deep modules (`deep-modules.md`) to push complexity *inside* the implementation rather than spreading it across the interface.

## The connection to Verify-RED

Every one of these rules makes Verify-RED cheaper. If the interface accepts dependencies, you can pass a fake and immediately observe the failure. If the function returns a result, you can assert on it directly without digging through state. If the surface is small, the test exercises exactly what matters and nothing else.

A test that is easy to fail correctly — predictably, for the right reason — is a test whose interface is well-designed.
