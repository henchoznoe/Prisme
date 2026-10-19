import XCTest
@testable import PrismeCore

final class RadialGeometryTests: XCTestCase {
    func testEveryVisibleSectorSelectsItsOwnLabelPosition() {
        let geometry = RadialGeometry()
        for count in 1...10 {
            for index in 0..<count {
                XCTAssertEqual(geometry.segmentIndex(at: geometry.labelCenter(for: index, count: count), count: count), index)
            }
        }
    }

    func testCenterAndOutsideCannotAccidentallyConvert() {
        let geometry = RadialGeometry()
        XCTAssertNil(geometry.segmentIndex(at: CGPoint(x: 230, y: 230), count: 9))
        XCTAssertNil(geometry.segmentIndex(at: CGPoint(x: 230, y: 0), count: 9))
        XCTAssertNil(geometry.segmentIndex(at: CGPoint(x: 230, y: 400), count: 0))
        XCTAssertEqual(geometry.segmentIndex(at: CGPoint(x: 230, y: 400), count: 4), 0)
        XCTAssertEqual(geometry.segmentIndex(at: CGPoint(x: 400, y: 230), count: 4), 1)
        XCTAssertEqual(geometry.segmentIndex(at: CGPoint(x: 230, y: 60), count: 4), 2)
        XCTAssertEqual(geometry.segmentIndex(at: CGPoint(x: 60, y: 230), count: 4), 3)
    }
}
