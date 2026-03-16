enum SimulatorError: Error {
    case deviceNotFound(destination: String)
    case bootTimeout(udid: String)
    case cloneFailed(udid: String)
}
