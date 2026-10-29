import Testing

@testable import SwiftMutationTesting

@Suite("MutantQueue")
struct MutantQueueTests {
    @Test("Given three mutants, when taken one by one, then they come in order and then nothing")
    func nextHandsTheMutantsOutInOrder() async {
        let queue = MutantQueue(warmMutants(3))

        let taken = [await queue.next(), await queue.next(), await queue.next(), await queue.next()]

        #expect(taken.map { $0?.index } == [0, 1, 2, nil])
    }

    @Test("Given one mutant taken, when drained, then the rest come out at once and the queue is empty")
    func drainEmptiesTheQueue() async {
        let queue = MutantQueue(warmMutants(3))
        _ = await queue.next()

        let drained = await queue.drain()

        #expect(drained.map(\.index) == [1, 2])
        #expect(await queue.next() == nil)
        #expect(await queue.drain().isEmpty)
    }

    // MARK: - Private

    private func warmMutants(_ count: Int) -> [IncompatibleMutantExecutor.WarmMutant] {
        (0 ..< count).map {
            IncompatibleMutantExecutor.WarmMutant(
                index: $0, mutant: makeMutantDescriptor(id: "m\($0)"), content: "let x = \($0)"
            )
        }
    }
}
