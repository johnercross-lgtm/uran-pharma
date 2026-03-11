import SwiftUI

struct ExtempPatientFieldsPanel: View {
    @Binding var isExpanded: Bool
    let patientName: Binding<String>
    let prescriptionNumber: Binding<String>
    let patientDobText: Binding<String>
    let patientAgeYearsText: Binding<String>
    let doctorFullName: Binding<String>
    let clinicName: Binding<String>
    let blankType: Binding<RxBlankType>

    var body: some View {
        DisclosureGroup("Поля для рецепта", isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                TextField("ФИО пациента", text: patientName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled(true)

                TextField("№ рецепта", text: prescriptionNumber)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)

                TextField("Дата рождения (ДД.ММ.ГГГГ)", text: patientDobText)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)

                TextField("Вік дитини (роки)напр. 0.5 / 3 / 12", text: patientAgeYearsText)
                    .keyboardType(.decimalPad)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)

                TextField("Врач", text: doctorFullName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled(true)

                TextField("Учреждение", text: clinicName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled(true)

                Picker("Тип бланка", selection: blankType) {
                    ForEach(RxBlankType.allCases) { type in
                        Text(type.title).tag(type)
                    }
                }
                .pickerStyle(.menu)
            }
            .padding(.top, 8)
        }
    }
}
