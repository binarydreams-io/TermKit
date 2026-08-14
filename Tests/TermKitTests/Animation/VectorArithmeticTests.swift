import Testing

@testable import TermKit

struct VectorArithmeticTests {
    @Test("Animatable pairs interpolate both components")
    func pairInterpolation() {
        let value = AnimatablePair<Double, Double>.interpolated(
            from: AnimatablePair(0, 10),
            to: AnimatablePair(10, 30),
            progress: 0.25
        )

        #expect(value == AnimatablePair(2.5, 15))
        #expect(value.magnitudeSquared == 231.25)
    }

    @Test("Empty animatable data is a zero vector")
    func emptyData() {
        var value = EmptyAnimatableData.zero
        value.scale(by: 10)

        #expect(value == .zero)
        #expect(value.magnitudeSquared == 0)
    }
}
