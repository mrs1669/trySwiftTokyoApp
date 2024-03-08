import ComposableArchitecture
import DataClient
import Foundation
import SwiftUI
import SharedModels
import TipKit

@Reducer
public struct Schedule {
  enum Days: LocalizedStringKey, Equatable, CaseIterable, Identifiable {
    case day1 = "Day 1"
    case day2 = "Day 2"
    case day3 = "Day 3"

    var id: Self { self }
  }

  @ObservableState
  public struct State: Equatable {

    var path = StackState<Path.State>()
    var selectedDay: Days = .day1
    var searchText: String = ""
    var isSearchBarPresented: Bool = false
    var day1: Conference?
    var day2: Conference?
    var workshop: Conference?

    public init() {
      try! Tips.configure([.displayFrequency(.immediate)])
    }
  }

  public enum Action: BindableAction, ViewAction {
    case binding(BindingAction<State>)
    case path(StackAction<Path.State, Path.Action>)
    case view(View)

    public enum View {
      case onAppear
      case disclosureTapped(Session)
      case mapItemTapped
    }
  }

  @Dependency(DataClient.self) var dataClient
  @Dependency(\.openURL) var openURL

  public init() {}

  public var body: some ReducerOf<Self> {
    BindingReducer()
    Reduce { state, action in
      switch action {
        case .view(.onAppear):
          state.day1 = try! dataClient.fetchDay1()
          state.day2 = try! dataClient.fetchDay2()
          state.workshop = try! dataClient.fetchWorkshop()
          return .none
        case let .view(.disclosureTapped(session)):
          guard let description = session.description, let speakers = session.speakers else { return .none }
          state.path.append(.detail(
            .init(
              title: session.title,
              description: description,
              requirements: session.requirements,
              speakers: speakers
            )
          )
          )
          return .none
        case .view(.mapItemTapped):
          return .run { _ in
            let url = String(localized: "Guidance URL", bundle: .module)
            await openURL(URL(string: url)!)
          }
        case .binding, .path:
          return .none
      }
    }
    .forEach(\.path, action: \.path) {
      Path()
    }
  }

  @Reducer
  public struct Path {
    @ObservableState
    public enum State: Equatable {
      case detail(ScheduleDetail.State)
    }

    public enum Action {
      case detail(ScheduleDetail.Action)
    }

    public var body: some ReducerOf<Path> {
      Scope(state: \.detail, action: \.detail) {
        ScheduleDetail()
      }
    }
  }
}

@ViewAction(for: Schedule.self)
public struct ScheduleView: View {

  @Bindable public var store: StoreOf<Schedule>
  let mapTip: MapTip = .init()

  public init(store: StoreOf<Schedule>) {
    self.store = store
  }

  public var body: some View {
    NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
      root
    } destination: { store in
      switch store.state {
        case .detail:
          if let store = store.scope(state: \.detail, action: \.detail) {
            ScheduleDetailView(store: store)
          }
      }
    }
  }

  @ViewBuilder
  var root: some View {
    ScrollView {
      Picker("Days", selection: $store.selectedDay) {
        ForEach(Schedule.Days.allCases) { day in
          Text(day.rawValue, bundle: .module)
        }
      }
      .pickerStyle(.segmented)
      .padding(.horizontal)
      switch store.selectedDay {
        case .day1:
          if let day1 = store.day1 {
            conferenceList(conference: day1)
          } else {
            Text("")
          }
        case .day2:
          if let day2 = store.day2 {
            conferenceList(conference: day2)
          } else {
            Text("")
          }
        case .day3:
          if let workshop = store.workshop {
            conferenceList(conference: workshop)
          } else {
            Text("")
          }
      }
    }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Image(systemName: "map")
          .onTapGesture {
            send(.mapItemTapped)
          }
          .popoverTip(mapTip)

      }
    }
    .onAppear(perform: {
      send(.onAppear)
    })
    .navigationTitle(Text("Schedule", bundle: .module))
    .searchable(text: $store.searchText, isPresented: $store.isSearchBarPresented)
  }

  @ViewBuilder
  func conferenceList(conference: Conference) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(conference.date, style: .date)
        .font(.title2)
      ForEach(conference.schedules, id: \.self) { schedule in
        VStack(alignment: .leading, spacing: 4) {
          Text(schedule.time, style: .time)
            .font(.subheadline.bold())
          ForEach(schedule.sessions, id: \.self) { session in
            if session.description != nil {
              Button(action: {
                send(.disclosureTapped(session))
              }, label: {
                listRow(session: session)
                  .padding()
              })
              .background(
                Color(uiColor: .secondarySystemBackground)
                  .clipShape(RoundedRectangle(cornerRadius: 8))
              )
            } else {
              listRow(session: session)
                .padding()
                .background(
                  Color(uiColor: .secondarySystemBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                )
            }
          }
        }
      }
    }
    .padding()
  }

  @ViewBuilder
  func listRow(session: Session) -> some View {
    HStack(spacing: 8) {
      VStack {
        if let speakers = session.speakers {
          ForEach(speakers, id: \.self) { speaker in
            Image(speaker.imageName, bundle: .module)
              .resizable()
              .aspectRatio(contentMode: .fit)
              .clipShape(Circle())
              .background(
                Color(uiColor: .systemBackground)
                  .clipShape(Circle())
              )
              .frame(width: 60)
          }
        } else {
          Image(.tokyo)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .clipShape(Circle())
            .frame(width: 60)
        }
      }
      VStack(alignment: .leading) {
        Text(LocalizedStringKey(session.title), bundle: .module)
          .font(.title3)
          .multilineTextAlignment(.leading)
        if let speakers = session.speakers {
          Text(ListFormatter.localizedString(byJoining: speakers.map(\.name)))
            .foregroundStyle(Color.init(uiColor: .label))
        }
        if let summary = session.summary {
          Text(LocalizedStringKey(summary), bundle: .module)
            .foregroundStyle(Color(uiColor: .secondaryLabel))
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

struct MapTip: Tip, Equatable {
  var title: Text = Text("Go Shibuya First, NOT Garden", bundle: .module)
  var message: Text? = Text("There are two kinds of Bellesalle in Shibuya. Learn how to get from Shibuya Station to \"Bellesalle Shibuya FIRST\". ", bundle: .module)
  var image: Image? = .init(systemName: "map.circle.fill")
}

#Preview {
  ScheduleView(store: .init(initialState: .init(), reducer: {
    Schedule()
  }))
}
